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

# TODO: rename auto_wire => static
      return Nested.Static(callable, id: id, auto_wire: auto_wire) if auto_wire.any?

      # no {auto_wire}
      return Nested.Dynamic(callable, id: id)
    end

    # @private
    class Nested < Trailblazer::Activity::Railway
      # TODO: make this {Activity::KeepOuterExecContext} Interim or something
      # TODO: remove Strategy.call and let runner do this.
      def self.call(args, **circuit_options)
        # by calling the internal {Activity} directly we skip setting a new {:exec_context}
        to_h[:activity].(args, **circuit_options)
      end

      def self.operation_class # TODO: remove once we don't need the deprecation anymore.
        Operation
      end

      # Creates the "decider" activity that looks as follows.
      #   step decider_task
      #   ..your code...
      # It is used for both Dynamic and Static.
      def self.decider_activity_for(decider, id:, &block)
        decider_task = Activity::Circuit::TaskAdapter.Binary(
          decider,
          adapter_class: Activity::Circuit::TaskAdapter::Step::AssignVariable,
          variable_name: :nested_activity
        )
        # decider_task is a circuit-interface compatible task that internally calls {user_proc}
        # and assigns the return value to {ctx[:nested_activity]}.

        nesting_activity = Class.new(Nested) do
          step task: decider_task # always run the decider!

          instance_exec(&block)
        end
      end

      def self.nesting_activity_step_for(decider_activity, id:, **options_for_decider_activity, &block)
        nesting_activity = Class.new(Nested) do
          # The separated decider_activity is so we can discard {:nested_activity} and
          # keep any decider computation within {decider_activity}.
          step Subprocess(decider_activity).merge({
            id: :decide,
            In()  => ->(ctx, **) { ctx }, # FIXME: generic solution for this.
            Out() => [], # discard of {ctx[:nested_activity]}.
          }).merge(options_for_decider_activity)

          instance_exec(&block)
        end

        Activity::Railway.Subprocess(nesting_activity).merge(id: id)
      end

      # Dynamic is without auto_wire where we don't even know what *could* be the actual
      # nested activity until it's runtime.
      def self.Dynamic(decider, id:)
        decider_activity = decider_activity_for(decider, id: id) do
          step task:  Dynamic.method(:decision_result_to_flow_options),
               id:    :decision_result_to_flow_options
        end

        nesting_activity = nesting_activity_step_for(decider_activity, id: id) do
          step task:  Dynamic.method(:call_dynamic_nested_activity),
               id:    :call_dynamic_nested_activity
        end
      end

      class Dynamic
        SUCCESS_SEMANTICS = [:success, :pass_fast] # TODO: make this injectable/or get it from operation.
        # As we're discarding the decider_activity's ctx, the actual decision
        # is put to the {flow_options}.
        def self.decision_result_to_flow_options((ctx, flow_options), **circuit_options)
          decision = ctx[:nested_activity]

          new_flow_options = flow_options.merge(decision: decision)

          return Activity::Right, [ctx, new_flow_options]
        end

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
        # dispatch is wired to each possible Activity.

        dispatch_outputs = auto_wire.collect do |activity|
          [Activity::Railway.Output(activity, "decision:#{activity}"), Activity::Railway.End("decision:#{activity}")]
        end.to_h

        decider_activity = decider_activity_for(decider, id: id) do
          step({task: Static.method(:dispatch), id: :dispatch_to_terminus}.merge(dispatch_outputs))
        end

        decider_outputs = auto_wire.collect do |activity|
          [Activity::Railway.Output("decision:#{activity}"), Activity::Railway.Track(activity)]
        end.to_h

        nesting_activity_step_for(decider_activity, id: id, **decider_outputs) do
          auto_wire.each do |activity|
            activity_step = Subprocess(activity)

            outputs = activity_step[:outputs]

            # TODO: detect if we have two identical "special" termini.
            output_wirings = outputs.collect do |semantic, output|
              [Output(semantic), End(semantic)]
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
        def self.dispatch((ctx, flow_options), **circuit_options)
          nested_activity = ctx[:nested_activity] # we use the decision class as a signal.

          return nested_activity, [ctx, flow_options]
        end
      end

    end # Nested
  end
end
