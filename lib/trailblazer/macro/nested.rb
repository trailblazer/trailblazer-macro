# per default, everything we pass into a circuit is immutable. it's the ops/act's job to allow writing (via a Context)
module Trailblazer
  module Macro
    # {Nested} macro.
    def self.Nested(callable, id: "Nested(#{callable})")
      if callable.is_a?(Class) && callable < Nested.operation_class
        return Nested.operation_class.Subprocess(callable)
      end

      # dynamic
      task = Nested::Dynamic.new(callable)

      merge = [
        [Activity::TaskWrap::Pipeline.method(:insert_before), "task_wrap.call_task", ["Nested.compute_nested_activity", task.method(:compute_nested_activity)]],
        [Activity::TaskWrap::Pipeline.method(:insert_after),  "task_wrap.call_task", ["Nested.compute_return_signal", task.method(:compute_return_signal)]],
      ]

      task_wrap_extension = Activity::TaskWrap::Extension(merge: merge)

      {
        task:       task,
        id:         id,
        extensions: [task_wrap_extension],
        outputs:    task.outputs,
      }
    end

    # @private
    module Nested
      def self.operation_class
        Operation
      end

      # For dynamic `Nested`s that do not expose an {Activity} interface.
      # Since we do not know its outputs, we have to map them to :success and :failure, only.
      #
      # This is what {Nested} in 2.0 used to do, where the outcome could only be true/false (or success/failure).
      class Dynamic
        def initialize(nested_activity_decider)
          @nested_activity_decider = Option::KW(nested_activity_decider)

          @outputs         = {
            :success => Activity::Output(Activity::Railway::End::Success.new(semantic: :success), :success),
            :failure => Activity::Output(Activity::Railway::End::Failure.new(semantic: :failure), :failure)
          }
        end

        attr_reader :outputs

        # TaskWrap step.
        def compute_nested_activity(wrap_ctx, original_args)
          (ctx, _), original_circuit_options = original_args

          # TODO: evaluate the option to get the actual "object" to call.
          activity = @nested_activity_decider.(ctx, original_circuit_options)

          # Overwrite :task so task_wrap.call_task will call this activity.
          # This is a trick so we don't have to repeat logic from #call_task here.
          wrap_ctx[:task] = activity

          return wrap_ctx, original_args
        end

        def compute_return_signal(wrap_ctx, original_args)
          # Translate the genuine nested signal to the generic Dynamic end (success/failure, only).
          # Note that here we lose information about what specific event was emitted.
          wrap_ctx[:return_signal] = wrap_ctx[:return_signal].kind_of?(Activity::Railway::End::Success) ?
            @outputs[:success].signal : @outputs[:failure].signal

          return wrap_ctx, original_args
        end
      end
    end
  end
end
