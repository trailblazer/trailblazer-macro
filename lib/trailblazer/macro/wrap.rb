module Trailblazer
  module Macro
    module Wrap
      class Atom < DSL::Atom
        # Build the wrap node via the normalizer.
        def call(*, default_options:, exec_context: default_options.fetch(:exec_context), **) # called via Normalizer.evaluate_macro
          handler_for_wrap = options.fetch(:handler_for_wrap)
          block = options.fetch(:block)
          id = options.fetch(:id)

          Wrap.build_node(handler_for_wrap: handler_for_wrap, block: block, id: id, exec_context: exec_context)
        end
      end

      def self.build_node(handler_for_wrap:, block:, id:, exec_context:)
        block_activity, outputs = Macro.block_activity_for(nil, exec_context: exec_context, &block)

        adds_for_translate_signal = build_adds_for_translate_signal(outputs)

        options_for_node = {
          Activity::Railway.Output(:failure_from_wrap_handler, signal: Activity::Left) => Activity::Railway.Track(:failure),
          Activity::Railway.Output(:success_from_wrap_handler, signal: Activity::Right) => Activity::Railway.Track(:success), # TODO: test this explicitly, return it from the handler.
          outputs: outputs,
          id: id,
          node_for_call_task: Wrap::Node[block_activity, Circuit::Processor, options: {handler_for_wrap: handler_for_wrap}],
          adds_for_task_wrap: adds_for_translate_signal,
        }

        return options_for_node
      end

      def self.build_adds_for_translate_signal(outputs)
        [
          [
            :"wrap.translate_signal",
            Circuit::Node::Scoped[Runtime.method(:translate_signal), Circuit::Task::Adapter::LibInterface, merge_to_lib_ctx: {outputs: outputs}],
            :after, :"task_wrap.call_task"
          ]
        ]
      end

      module Runtime
        # Step in taskWrap after the {Wrap} node.
        def self.translate_signal(lib_ctx, flow_options, signal, outputs:, **)
          translated_signals = {
            Activity::Right               => :success,
            Activity::Left                => :failure,
            Activity::FastTrack::Signal::PassFast => :pass_fast,
            Activity::FastTrack::Signal::FailFast => :fail_fast,
          }

          if semantic = translated_signals[signal]
            signal = outputs.fetch(semantic).signal # the new signal is not Left, but the respective terminus from the {block_activity}.
          end

          return lib_ctx, flow_options, signal
        end
      end

      module Helper
        def Wrap(handler_for_wrap, id: Macro.id_for(handler_for_wrap, macro: :Wrap), &block)
          return Macro::Wrap::Atom.new({handler_for_wrap: handler_for_wrap, block: block, id: id})
        end
      end

      class Node < Circuit::Node
        def call(lib_ctx, flow_options, signal, **circuit_options)
          handler_for_wrap = options.fetch(:handler_for_wrap)

          block_for_yield = ->(*args) { interface.(task, lib_ctx, flow_options, signal, **circuit_options) }

          lib_ctx, flow_options, signal = handler_for_wrap.(lib_ctx, flow_options, signal, **circuit_options, &block_for_yield)

          return lib_ctx, flow_options, signal
        end
      end
    end # Wrap
    # TODO: {user_wrap}: rename to {wrap_handler}.
  end
end
