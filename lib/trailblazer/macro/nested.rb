# per default, everything we pass into a circuit is immutable. it's the ops/act's job to allow writing (via a Context)
module Trailblazer
  module Macro
    # {Nested} macro.
    def self.Nested(callable, id: "Nested(#{callable})", auto_wire: [])
      if callable.is_a?(Class) && callable < Nested.operation_class
        warn %{[Trailblazer] Using the `Nested()` macro with operations and activities is deprecated. Replace `Nested(Create)` with `Subprocess(Create)`.}
        return Nested.operation_class.Subprocess(callable)
      end

      # dynamic
      task = Nested::Dynamic.new(callable, auto_wire: auto_wire)

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
      class Dynamic
        STATIC_OUTPUTS = {
          :success => Activity::Output(Activity::Railway::End::Success.new(semantic: :success), :success),
          :failure => Activity::Output(Activity::Railway::End::Failure.new(semantic: :failure), :failure),
        }

        def initialize(nested_activity_decider, auto_wire: [])
          @nested_activity_decider  = Option::KW(nested_activity_decider)
          @known_activities         = Array(auto_wire)
          @outputs                  = compute_task_outputs
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
          # NOOP when @auto_wire is given as all possible signals have been registered already.
          if @known_activities.empty?
            # Translate the genuine nested signal to the generic Dynamic end (success/failure, only).
            # Note that here we lose information about what specific event was emitted.
            wrap_ctx[:return_signal] = wrap_ctx[:return_signal].kind_of?(Activity::Railway::End::Success) ?
              @outputs[:success].signal : @outputs[:failure].signal
          end

          return wrap_ctx, original_args
        end

        private def compute_task_outputs
          # If :auto_wire is empty, we map outputs to :success and :failure only, for backward compatibility.
          # This is what {Nested} in 2.0 used to do, where the outcome could only be true/false (or success/failure).
          return STATIC_OUTPUTS if @known_activities.empty?

          # Merge activity#outputs from all given auto_wirable activities to wire up for this dynamic task.
          @known_activities.inject({}) do |outputs, activity|
            # TODO: Replace this when it's helper gets added.
            activity_outputs = Hash[activity.to_h[:outputs].collect{ |output| [output.semantic, output] }]

            { **outputs, **activity_outputs }
          end
        end
      end
    end
  end
end
