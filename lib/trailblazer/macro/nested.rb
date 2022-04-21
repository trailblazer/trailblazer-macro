# per default, everything we pass into a circuit is immutable. it's the ops/act's job to allow writing (via a Context)
module Trailblazer
  module Macro
    # {Nested} macro.
    def self.Nested(callable, id: "Nested(#{callable})", auto_wire: [])
      if callable.is_a?(Class) && callable < Nested.operation_class
        caller_location = caller_locations(2, 1)[0]
        warn "[Trailblazer]#{caller_location.absolute_path}: " \
             "Using the `Nested()` macro with operations and activities is deprecated. " \
             "Replace `Nested(#{callable})` with `Subprocess(#{callable})`."

        return Activity::Railway.Subprocess(callable)
      end

      task, outputs, compute_legacy_return_signal = Nested.Dynamic(callable, auto_wire: auto_wire)

      merge = [
        [Activity::TaskWrap::Pipeline.method(:insert_before), "task_wrap.call_task", ["Nested.compute_nested_activity", task]],
      ]

      if compute_legacy_return_signal
        merge << [Activity::TaskWrap::Pipeline.method(:insert_after),  "task_wrap.call_task", ["Nested.compute_return_signal", compute_legacy_return_signal]]
      end

      task_wrap_extension = Activity::TaskWrap::Extension(merge: merge)

      {
        task:       task,
        id:         id,
        extensions: [task_wrap_extension],
        outputs:    outputs,
      }
    end

    # @private
    module Nested
      def self.operation_class
        Operation
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
      def self.Dynamic(nested_activity_decider, auto_wire:)
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

      class Dynamic
        def initialize(nested_activity_decider)
          @nested_activity_decider = Trailblazer::Option(nested_activity_decider)
        end

        # TaskWrap step.
        def call(wrap_ctx, original_args)
          (ctx, _), original_circuit_options = original_args

          # TODO: evaluate the option to get the actual "object" to call.
          activity = @nested_activity_decider.(ctx, keyword_arguments: ctx.to_hash, **original_circuit_options)

          # Overwrite :task so task_wrap.call_task will call this activity.
          # This is a taskWrap trick so we don't have to repeat logic from #call_task here.
          wrap_ctx[:task] = activity

          return wrap_ctx, original_args
        end

        # TODO: remove me when we make {:auto_wire} mandatory.
        class ComputeLegacyReturnSignal
          SUCCESS_SEMANTICS = [:success, :pass_fast] # TODO: make this injectable/or get it from operation.

          def initialize(outputs)
            @outputs = outputs # not needed for auto_wire!
          end

          def call(wrap_ctx, original_args)
            actual_semantic  = wrap_ctx[:return_signal].to_h[:semantic]
            applied_semantic = SUCCESS_SEMANTICS.include?(actual_semantic) ? :success : :failure

            wrap_ctx[:return_signal] = @outputs.fetch(applied_semantic).signal

            return wrap_ctx, original_args
          end
        end # ComputeLegacyReturnSignal
      end
    end
  end
end
