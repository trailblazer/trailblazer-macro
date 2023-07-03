require "forwardable"
require "trailblazer/activity/dsl/linear"
require "trailblazer/operation" # TODO: remove this dependency

require "trailblazer/macro/strategy"
require "trailblazer/macro/model"
require "trailblazer/macro/model/find"
require "trailblazer/macro/policy"
require "trailblazer/macro/guard"
require "trailblazer/macro/pundit"
require "trailblazer/macro/nested"
require "trailblazer/macro/rescue"
require "trailblazer/macro/wrap"
require "trailblazer/macro/each"

module Trailblazer
  module Macro
      # TaskAdapter::AssignVariable
        # Run {user_proc} with "step interface" and assign its return value to ctx[@variable_name].
        # @private
        # This is experimental.
    class AssignVariable
        # name of the ctx variable we want to assign the return_value of {user_proc} to.
      def initialize(return_value_step, variable_name:)
        @return_value_step  = return_value_step
        @variable_name      = variable_name
      end

      def call((ctx, flow_options), **circuit_options)
        return_value, ctx = @return_value_step.([ctx, flow_options], **circuit_options)

        ctx[@variable_name] = return_value

        return return_value, ctx
      end
    end

    def self.task_adapter_for_decider(decider_with_step_interface, variable_name:)
      return_value_circuit_step = Activity::Circuit.Step(decider_with_step_interface, option: true)

      assign_task = AssignVariable.new(return_value_circuit_step, variable_name: variable_name)

      Activity::Circuit::TaskAdapter.new(assign_task) # call {assign_task} with circuit-interface, interpret result.
    end

    def self.block_activity_for(block_activity, &block)
      return block_activity, block_activity.to_h[:outputs] unless block_given?

      block_activity = Class.new(Activity::FastTrack, &block) # TODO: use Wrap() logic!
      block_activity.extend Each::Transitive

      return block_activity, block_activity.to_h[:outputs]
    end

    module IdFor
      module_function

      def call(user_proc, macro:, hint: nil, id: from_callable(user_proc, hint: hint))
        [macro, id].join("/")
      end

      def from_callable(user_proc, hint: nil)
        if user_proc.is_a?(Class)
          user_proc.to_s
        elsif user_proc.instance_of?(Method)
          "method(:#{user_proc.name})"
        else
          hint || rand(4)
        end
      end
    end

    def self.id_for(user_proc, **options)
      IdFor.(user_proc, **options)
    end
  end # Macro

  # All macros sit in the {Trailblazer::Macro} namespace, where we forward calls from
  # operations and activities to.

  module Activity::DSL::Linear::Helper
    Constants::Policy = Trailblazer::Macro::Policy
    Constants::Model  = Trailblazer::Macro::Model

    # Extending the {Linear::Helper} namespace is the canonical way to import
    # macros into Railway, FastTrack, Operation, etc.
    extend Forwardable
    def_delegators Trailblazer::Macro, :Model, :Nested, :Wrap, :Rescue, :Each
  end # Helper
end
