module Trailblazer
  module Macro
    # {Nested} macro.
    # DISCUSS: rename auto_wire => static
    def self.Nested(callable, id: Macro.id_for(callable, macro: :Nested, hint: callable), auto_wire: [])
      # Warn developers when they confuse Nested with Subprocess (for simple nesting, without a dynamic decider).
      if callable.is_a?(Class) && callable < Nested.operation_class
        caller_locations = caller_locations(1, 2)
        caller_location = caller_locations[0].to_s =~ /forwardable/ ? caller_locations[1] : caller_locations[0]

        Activity::Deprecate.warn caller_location,
          "Using the `Nested()` macro without a dynamic decider is deprecated.\n" \
          "To simply nest an activity or operation, replace `Nested(#{callable})` with `Subprocess(#{callable})`.\n" \
          "Check the Subprocess API docs to learn more about nesting: https://trailblazer.to/2.1/docs/activity.html#activity-wiring-api-subprocess"

        return Activity::Railway.Subprocess(callable)
      end

      task =
        if auto_wire.any?
          Nested.Static(callable, id: id, auto_wire: auto_wire)
        else # no {auto_wire}
          Nested.Dynamic(callable, id: id)
        end

      # |-- Nested.compute_nested_activity...Trailblazer::Macro::Nested::Decider
      # `-- task_wrap.call_task..............Method
      merge = [
        [Nested::Decider.new(callable), id: "Nested.compute_nested_activity", prepend: "task_wrap.call_task"],
      ]

      task_wrap_extension = Activity::TaskWrap::Extension::WrapStatic.new(extension: Activity::TaskWrap::Extension(*merge))

      Activity::Railway.Subprocess(task).merge( # FIXME: allow this directly in Subprocess
        id:         id,
        extensions: [task_wrap_extension],
      )
    end

    # @private
    # @api private The internals here are considered private and might change in the near future.
    #
    # We don't need to override {Strategy.call} here to prevent {:exec_context} from being changed.
    # The decider is run in the taskWrap before the {Nested} subclass is actually called.
    class Nested < Trailblazer::Activity::Railway
      def self.operation_class # TODO: remove once we don't need the deprecation anymore.
        Trailblazer::Activity::DSL::Linear::Strategy
      end

      # TaskWrap step to run the decider.
      # It's part of the API that the decider sees the original ctx.
      # So this has to be placed in tW because we this step needs to be run *before* In() filters
      # to resemble the behavior from pre 2.1.12.
      class Decider
        def initialize(nested_activity_decider)
          @nested_activity_decider = Activity::Circuit.Step(nested_activity_decider, option: true)
        end

        # TaskWrap API.
        def call(wrap_ctx, original_args)
          (ctx, flow_options), original_circuit_options = original_args

          # FIXME: allow calling a Step task without the Binary decision (in Activity::TaskAdapter).
          nested_activity, _ = @nested_activity_decider.([ctx, flow_options], **original_circuit_options) # no TaskWrap::Runner because we shall not trace!

          new_flow_options = flow_options.merge(
            decision: nested_activity
          )

          return wrap_ctx, [[ctx, new_flow_options], original_circuit_options]
        end
      end

      # Dynamic is without auto_wire where we don't even know what *could* be the actual
      # nested activity until it's runtime.
      def self.Dynamic(decider, id:)
        _task = Class.new(Macro::Nested) do
          step task: Dynamic.method(:call_dynamic_nested_activity),
               id:   :call_dynamic_nested_activity
        end
      end

      class Dynamic
        SUCCESS_SEMANTICS = [:success, :pass_fast] # TODO: make this injectable/or get it from operation.

        def self.call_dynamic_nested_activity((ctx, flow_options), runner:, **circuit_options)
          nested_activity       = flow_options[:decision]
          original_flow_options = flow_options.slice(*(flow_options.keys - [:decision]))

          host_activity = Dynamic.host_activity_for(activity: nested_activity)

          # TODO: make activity here that has only one step (plus In and Out config) which is {nested_activity}

          return_signal, (ctx, flow_options) = runner.(
            nested_activity,
            [ctx, original_flow_options], # pass {flow_options} without a {:decision}.
            runner:   runner,
            **circuit_options,
            activity: host_activity
          )

          return compute_legacy_return_signal(return_signal), [ctx, flow_options]
        end

        def self.compute_legacy_return_signal(return_signal)
          actual_semantic  = return_signal.to_h[:semantic]
          _applied_signal   = SUCCESS_SEMANTICS.include?(actual_semantic) ? Activity::Right : Activity::Left # TODO: we could also provide PassFast/FailFast.
        end

        # This is used in Nested and Each where some tasks don't have a corresponding, hard-wired
        # activity. This is needed for {TaskWrap.invoke} and the Debugging API in tracing.
        # @private
        def self.host_activity_for(activity:)
          Activity::TaskWrap.container_activity_for(
            activity,
            id: activity.to_s
          )
        end

      end

      # Code to handle [:auto_wire]. This is called "static" as you configure the possible activities at
      # compile-time. This is the recommended way.
      #
      # TODO: allow configuring Output of Nested per internal nested activity, e.g.
      #         step Nested(.., Id3Tag => {Output(:invalid_metadata) => ...}
      #       this will help when semantics overlap.
      #
      def self.Static(decider, id:, auto_wire:)
        decider_connectors = auto_wire.collect do |activity|
          [Activity::Railway.Output(activity, "decision:#{activity}"), Activity::Railway.Track(activity)]
        end.to_h

        _task = Class.new(Macro::Nested) do
          step(
            {
              task: Static.method(:return_route_signal),
              id:   :route_to_nested_activity, # returns the {nested_activity} signal
            }.merge(decider_connectors)
          )

          auto_wire.each do |activity|
            activity_step = Subprocess(activity)

            outputs = activity_step[:outputs]

            # TODO: detect if we have two identical "special" termini.
            output_wirings = outputs.collect do |semantic, output|
              [Output(semantic), End(semantic)] # this will add a new termins to this activity.
            end.to_h

            # Each nested activity is a Subprocess.
            # They have Output(semantic) => End(semantic) for each of their termini.
            step activity_step,
              {magnetic_to: activity}.merge(output_wirings)
              # failure and success are wired to respective termini of {nesting_activity}.
          end
        end
      end

      module Static
        def self.return_route_signal((ctx, flow_options), **circuit_options)
          nested_activity = flow_options[:decision] # we use the decision class as a signal.

          original_flow_options = flow_options.slice(*(flow_options.keys - [:decision]))

          return nested_activity, [ctx, original_flow_options]
        end
      end

    end # Nested
  end
end
