require "trailblazer/activity/dsl"
require "trailblazer/activity/variable_mapping"

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

      def call(ctx, flow_options, circuit_options)
        puts "yooo AssignVariable"
        ctx, flow_options, return_value = @return_value_step.(ctx, flow_options, circuit_options)

        ctx[@variable_name] = return_value

        return ctx, flow_options, Trailblazer::Activity::Right
      end
    end

    def self.task_adapter_for_decider(decider_with_step_interface, variable_name:)
      return_value_circuit_step = Activity::Step.build(decider_with_step_interface) # FIXME: this should be binary!

      AssignVariable.new(return_value_circuit_step, variable_name: variable_name)

raise "implement AssignVariable"
      Circuit::Builder.Pipeline(

      )
    end

    def self.block_activity_for(block_activity, &block)
      return block_activity, block_activity.to_h[:outputs] unless block_given?

      # block_activity = Class.new(Activity::FastTrack, &block) # TODO: use Wrap() logic!
      block_activity = Activity.FastTrack(&block) # TODO: use Wrap() logic!
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
          hint || rand
        end
      end
    end

    def self.id_for(user_proc, **options)
      IdFor.(user_proc, **options)
    end

    TOPOLOGY_BUILD_OPTIONS = {
      helpers: {
        Macro::Model::Helper => [:Model],
        # TODO:
  # def_delegators Trailblazer::Macro, :Model, :Nested, :Wrap, :Rescue, :Each
  # Constants::Policy = Trailblazer::Macro::Policy
  # Constants::Model  = Trailblazer::Macro::Model
      },
      constants: [Macro::Model::Constants],
      adds: []
    }
  end # Macro
end
