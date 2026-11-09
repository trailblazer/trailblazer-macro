require "trailblazer/activity/dsl"
require "trailblazer/activity/variable_mapping"

require "trailblazer/macro/dsl"
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
    class AssignVariable < Struct.new(:variable_name, keyword_init: true)
        # name of the ctx variable we want to assign the return_value of {user_proc} to.
      def call(lib_ctx, flow_options, value, target_ctx:, **)
        target_ctx[variable_name] = value

        return lib_ctx, flow_options, value.nil? ? Activity::Left : Activity::Right # DISCUSS: if id.nil?, we Left.
      end
    end

    def self.task_adapter_for_decider(decider_with_step_interface, variable_name:)
      invoke_provider_step = Activity::Step.build(decider_with_step_interface, binary: false) # FIXME: we cannot deviate to Left here
      assign_variable_step = AssignVariable.new(variable_name: variable_name)

      extract_id = Circuit::Builder.Pipeline(
        [:call_provider,   node: invoke_provider_step],
        [:assign_variable, assign_variable_step]
      )

      # Developer.puts  extract_id

      extract_id
    end

    def self.block_activity_for(block_activity, **options, &block)
      return block_activity, block_activity.to_h[:outputs] unless block_given?

      block_activity = Class.new(Activity::FastTrack)# do # TODO: use Wrap() logic!
      block_activity.config.builder.default_options.each { |_, dsl_options| dsl_options.merge!(**options) } # TODO: allow this via FastTrack().
      # puts "@@@@@ ??#{block_activity.config.builder.default_options[:step].inspect}"
      block_activity.instance_exec(&block)
      #   &block)
      # end
      # block_circuit, outputs = Activity.FastTrack(**options, &block) # TODO: use Wrap() logic!
      # pp block_activity

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

    ADDS_FOR_EVALUATE_MACRO = [
      :"macro.evaluate_macro", Circuit::Node[DSL::Normalizer.method(:evaluate_macro), Circuit::Task::Adapter::LibInterface],
      :before
    ]

    TOPOLOGY_BUILD_OPTIONS = {
      helpers: {
        Macro::Model::Helper => [:Model],
        Macro::Each::Helper => [:Each],
        Macro::Wrap::Helper => [:Wrap],
        # TODO:
  # def_delegators Trailblazer::Macro, :Model, :Nested, :Wrap, :Rescue, :Each
  # Constants::Policy = Trailblazer::Macro::Policy
  # Constants::Model  = Trailblazer::Macro::Model
      },
      constants: [
        Macro::Model::Constants,
        Macro::Policy::Constants,
      ],

      adds: [
        ADDS_FOR_EVALUATE_MACRO,
      ]
    }
  end # Macro
end
