module Trailblazer
  module Macro

    class Nested
      module Helper
        # {Nested} macro.
        def Nested(decider, id: Macro.id_for(decider, macro: :Nested, hint: decider), static: [])
          Atom.new({decider: decider, id: id, static: static})
        end
      end

      class Atom < DSL::Atom
        def call(*, default_options:, exec_context: default_options.fetch(:exec_context), **) # FIXME: move this to Atom.
          build_node(exec_context: exec_context, **options)
        end

        def build_node(exec_context:, decider:, static:, id:, **)
          task =
            if static.any?
              Nested.Static(decider, id: id, static: static, exec_context: exec_context)
            else
              Nested.Dynamic(decider, id: id)
            end

          return task
        end
      end
    end


    #   # |-- Nested.compute_nested_activity...Trailblazer::Macro::Nested::Decider
    #   # `-- task_wrap.call_task..............Method
    #   merge = [
    #     [Nested::Decider.new(callable), id: "Nested.compute_nested_activity", prepend: "task_wrap.call_task"],
    #   ]

    #   # DISCUSS: we could use fields{task_wrap_extensions} from the Nested activity here?
    #   task_wrap_extension = Activity::TaskWrap.Extension(*merge)

    #   Activity::Railway.Subprocess(task)
    #     .merge( # FIXME: allow this directly in Subprocess
    #       id: id,
    #       Activity::Railway.Extension() => task_wrap_extension,
    #     )
    # end

    # @private
    # @api private The internals here are considered private and might change in the near future.
    #
    # We don't need to override {Strategy.call} here to prevent {:exec_context} from being changed.
    # The decider is run in the taskWrap before the {Nested} subclass is actually called.
    class Nested# < Trailblazer::Activity::Railway
      # TaskWrap step to run the decider.
      # It's part of the API that the decider sees the original ctx.
      # So this has to be placed in tW because we this step needs to be run *before* In() filters
      # to resemble the behavior from pre 2.1.12.
      class Decider
        def initialize(nested_activity_decider)
          @nested_activity_decider = Activity::Circuit.Step(nested_activity_decider)
        end

        # TaskWrap API.
        def call(wrap_ctx, flow_options, circuit_options)
          # FIXME: allow calling a Step task without the Binary decision (in Activity::TaskAdapter).
          _, _, nested_activity = @nested_activity_decider.(wrap_ctx[:application_ctx], flow_options, circuit_options) # no TaskWrap::Runner because we shall not trace!

          new_flow_options = flow_options.merge(
            decision: nested_activity
          )

          return wrap_ctx, new_flow_options
        end
      end

      # Dynamic is without static where we don't even know what *could* be the actual
      # nested activity until it's runtime.
      def self.Dynamic(decider, id:)
        _task = Class.new(Macro::Nested) do
          step task: Dynamic.method(:call_dynamic_nested_activity),
               id:   :call_dynamic_nested_activity
        end
      end

      class Dynamic
        SUCCESS_SEMANTICS = [:success, :pass_fast] # TODO: make this injectable/or get it from operation.

        # TODO: couldn't we use the taskWrap here?
        def self.call_dynamic_nested_activity(ctx, flow_options, circuit_options)
          nested_activity       = flow_options[:decision]
          original_flow_options = flow_options.slice(*(flow_options.keys - [:decision]))
          runner                = circuit_options.fetch(:runner)

          host_activity = Dynamic.host_activity_for(activity: nested_activity)

          # TODO: make activity here that has only one step (plus In and Out config) which is {nested_activity}

          ctx, flow_options, return_signal = runner.(
            nested_activity,
            ctx, original_flow_options, # pass {flow_options} without a {:decision}.
            circuit_options.merge(
              activity: host_activity
            )
          )

          return ctx, flow_options, compute_legacy_return_signal(return_signal)
        end

        def self.compute_legacy_return_signal(return_signal)
          actual_semantic  = return_signal.to_h[:semantic]
          applied_signal   = SUCCESS_SEMANTICS.include?(actual_semantic) ? Activity::Right : Activity::Left # TODO: we could also provide PassFast/FailFast.
        end
      end

      # Code to handle [:static]. This is called "static" as you configure the possible activities at
      # compile-time. This is the recommended way.
      #
      # TODO: allow configuring Output of Nested per internal nested activity, e.g.
      #         step Nested(.., Id3Tag => {Output(:invalid_metadata) => ...}
      #       this will help when semantics overlap.
      def self.Static(decider, id:, static:, exec_context:)
        decider_node = Activity::Step.build(decider, exec_context: exec_context, binary: false) # TODO: we could allow {:lib_interface}.

        # Some mapping work necessary for the signals we return.
        id_2_activity = static.collect { |activity| [activity.to_s , activity]  }

        semantic_2_outputs = static.flat_map { |activity| Activity::Railway.Subprocess(activity)[:outputs].to_a }

        all_semantics = semantic_2_outputs.map(&:first).uniq
        public_outputs = all_semantics.collect { |semantic| [semantic, Activity::Output.new(semantic, semantic)] }.to_h

        nested_signal_2_public_signal = semantic_2_outputs.collect { |semantic, output| [output.signal, public_outputs.fetch(semantic).signal] }.to_h
        # DISCUSS: this hash is smaller than all the signals we have since Signal < Struct, and Struct thinks two termini with identical semantic are alike.


        node = Circuit::Builder.Node(
          *[
            [:decider, node: decider_node,
              connections: id_2_activity.collect { |id, activity| [activity, [id, activity]] }.to_h
            ],
            *id_2_activity.collect { |id, activity| [id, activity, Circuit::Processor, connections: Circuit::Resolver::Fixed.new(:translate_signal)] },
            # DISCUSS: translate_signal could be a separate step (easier to follow), or a resolver?
            [:translate_signal, Runtime::TranslateSignal.new(nested_signal_2_public_signal)]
          ]
        )

        return {node_for_call_task: node, outputs: public_outputs, id: id}
      end

      module Runtime
        class TranslateSignal < Struct.new(:signal_map)
          def call(lib_ctx, flow_options, signal_from_nested, **)
            return lib_ctx, flow_options, signal_map.fetch(signal_from_nested)
          end
        end
      end
    end # Nested
  end
end
