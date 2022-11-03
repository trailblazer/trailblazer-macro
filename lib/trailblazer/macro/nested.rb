module Trailblazer
  module Macro
    # {Nested} macro.
# TODO: rename auto_wire => static
    def self.Nested(callable, id: "Nested(#{callable})", auto_wire: [])
      # Warn developers when they confuse Nested with Subprocess (for simple nesting, without a dynamic decider).
      if callable.is_a?(Class) && callable < Nested.operation_class
        caller_location = caller_locations(2, 1)[0]
        warn "[Trailblazer] #{caller_location.absolute_path}:#{caller_location.lineno} " \
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
    class Nested < Trailblazer::Activity::Railway
      # TODO: make this {Activity::KeepOuterExecContext} Interim or something
      # TODO: remove Strategy.call and let runner do this.
      def self.call(args, **circuit_options)
        # by calling the internal {Activity} directly we skip setting a new {:exec_context}
        to_h[:activity].(args, **circuit_options)
      end

      def self.operation_class # TODO: remove once we don't need the deprecation anymore.
        Trailblazer::Activity::DSL::Linear::Strategy
      end

      # TaskWrap step to run the decider.
      # It's part of the API that the decider sees the original ctx.
      # So this has to be placed in tW because we this step needs to be run *before* In() filters
      # to resemble the behavior from pre 2.1.12.
      class Decider
        def initialize(nested_activity_decider)
          @nested_activity_decider = Activity::Circuit::TaskAdapter.Binary(nested_activity_decider)
        end

        # TaskWrap API.
        def call(wrap_ctx, original_args)
          (ctx, flow_options), original_circuit_options = original_args

          # FIXME: allow calling a Step task without the Binary decision (in Activity::TaskAdapter).
          nested_activity = @nested_activity_decider.call_FIXME([ctx, flow_options], **original_circuit_options) # no TaskWrap::Runner because we shall not trace!

          new_flow_options = flow_options.merge(
            decision: nested_activity
          )

          return wrap_ctx, [[ctx, new_flow_options], original_circuit_options]
        end
      end

      # Dynamic is without auto_wire where we don't even know what *could* be the actual
      # nested activity until it's runtime.
      def self.Dynamic(decider, id:)
        task = Class.new(Macro::Nested) do
          step task: Dynamic.method(:call_dynamic_nested_activity),
               id:   :call_dynamic_nested_activity
        end

        task
      end

      class Dynamic
        SUCCESS_SEMANTICS = [:success, :pass_fast] # TODO: make this injectable/or get it from operation.

        def self.call_dynamic_nested_activity((ctx, flow_options), runner:, **circuit_options)
          nested_activity       = flow_options[:decision]
          original_flow_options = flow_options.slice(*(flow_options.keys - [:decision]))

          hosting_activity = {
            nodes:        [Trailblazer::Activity::NodeAttributes.new(nested_activity.to_s, nil, nested_activity)],
            wrap_static:  {nested_activity => Trailblazer::Activity::TaskWrap.initial_wrap_static},
          }

          # TODO: make activity here that has only one step (plus In and Out config) which is {nested_activity}

          return_signal, (ctx, flow_options) = runner.(
            nested_activity,
            [ctx, original_flow_options], # pass {flow_options} without a {:decision}.
            runner:   runner,
            **circuit_options,
            activity: hosting_activity
          )

          return compute_legacy_return_signal(return_signal), [ctx, flow_options]
        end

        def self.compute_legacy_return_signal(return_signal)
          actual_semantic  = return_signal.to_h[:semantic]
          applied_signal   = SUCCESS_SEMANTICS.include?(actual_semantic) ? Activity::Right : Activity::Left # TODO: we could also provide PassFast/FailFast.
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
        decider_outputs = auto_wire.collect do |activity|
          [Activity::Railway.Output(activity, "decision:#{activity}"), Activity::Railway.Track(activity)]
        end.to_h

        Class.new(Macro::Nested) do
          step(
            {
              task: Static.method(:return_route_signal),
              id:   :route_to_nested_activity, # returns the {nested_activity} signal
            }.merge(decider_outputs)
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
