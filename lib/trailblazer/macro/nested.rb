# per default, everything we pass into a circuit is immutable. it's the ops/act's job to allow writing (via a Context)
module Trailblazer
  module Macro
    # {Nested} macro.
    # @api private The internals here are considered private and might change in the near future.
    def self.Nested(callable, id: "Nested(#{callable})", auto_wire: [])
      if callable.is_a?(Class) && callable < Nested.operation_class
        caller_location = caller_locations(2, 1)[0]
        warn "[Trailblazer]#{caller_location.absolute_path}: " \
             "Using the `Nested()` macro with operations and activities is deprecated. " \
             "Replace `Nested(#{callable})` with `Subprocess(#{callable})`."

        return Activity::Railway.Subprocess(callable)
      end







      # no {auto_wire}
      return Nested::Dynamic(callable, id: id)
    end
# TODO: auto_wire => static

    # @private
    class Nested < Trailblazer::Activity::Railway
      # TODO: make this {Activity::KeepOuterExecContext} Interim or something
      # TODO: remove Strategy.call and let runner do this.
      def self.call(args, **circuit_options)
        # by calling the internal {Activity} directly we skip setting a new {:exec_context}
        to_h[:activity].(args, **circuit_options)
      end

      def self.operation_class
        Operation
      end

      # Dynamic is without auto_wire where we don't even know what *could* be the actual
      # nested activity until it's runtime.
      def self.Dynamic(decider, id:)
        decider_task = Activity::Circuit::TaskAdapter.Binary(
          decider,
          adapter_class: Activity::Circuit::TaskAdapter::Step::AssignVariable,
          variable_name: :nested_activity
        )
        # decider_task is a circuit-interface compatible task that internally calls {user_proc}
        # and assigns the return value to {ctx[:nested_activity]}.

        nesting_activity = Class.new(Macro::Nested) do
          step task: decider_task
          step task: Dynamic.method(:call_dynamic_nested), id: :call_dynamic_nested
        end

        Activity::Railway.Subprocess(nesting_activity).merge(id: id)
      end

      class Dynamic
        SUCCESS_SEMANTICS = [:success, :pass_fast] # TODO: make this injectable/or get it from operation.

        def self.call_dynamic_nested((ctx, flow_options), runner:, **circuit_options)
          nested_activity = ctx[:nested_activity]

          hosting_activity = {
            nodes:        [Trailblazer::Activity::NodeAttributes.new(nested_activity.to_s, nil, nested_activity)],
            wrap_static:  {nested_activity => Trailblazer::Activity::TaskWrap.initial_wrap_static},
          }

          return_signal, (ctx, flow_options) = runner.(nested_activity, [ctx, flow_options], runner: runner, **circuit_options, activity: hosting_activity)

          actual_semantic  = return_signal.to_h[:semantic]
          applied_signal   = SUCCESS_SEMANTICS.include?(actual_semantic) ? Activity::Right : Activity::Left # TODO: we could also provide PassFast/FailFast.

          return applied_signal, [ctx, flow_options]
        end
      end



      # For dynamic `Nested`s that do not expose an {Activity} interface.
      #
      # Dynamic doesn't automatically connect outputs of runtime {Activity}
      # at compile time (as we don't know which activity will be nested, obviously).
      # So by default, it only connects good old success/failure ends. But it is also
      # possible to connect all the ends of all possible dynamic activities
      # by passing their list to {:auto_wire} option.
      #
      # step Nested(:compute_nested, auto_wire: [Create, Update])
      def self.___Dynamic(nested_activity_decider, auto_wire:)
        if auto_wire.empty?
          is_legacy = true # no auto_wire means we need to compute the legacy return signal.
          auto_wire = [Class.new(Activity::Railway)]
        end

        outputs = outputs_for(auto_wire)
        task    = Dynamic.new(nested_activity_decider)
        compute_legacy_return_signal = Dynamic::ComputeLegacyReturnSignal.new(outputs) if is_legacy

        return task, outputs, compute_legacy_return_signal
      end

      # Go through the list of all possible nested activities and compile the total sum of possible outputs.
      # FIXME: WHAT IF WE HAVE TWO IDENTICALLY NAMED OUTPUTS?
      # @private
      def self.outputs_for(activities)
        activities.map do |activity|
          Activity::Railway.Subprocess(activity)[:outputs]
        end.inject(:merge)
      end
    end
  end
end
