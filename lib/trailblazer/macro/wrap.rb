module Trailblazer
  module Macro
    module Wrap
      class Atom < DSL::Atom
        # Build the wrap node via the normalizer.
        def call(*, default_options:, exec_context: default_options.fetch(:exec_context), **) # called via Normalizer.evaluate_macro
          Wrap.build_node(**options, exec_context: exec_context)
        end
      end

      def self.build_node(handler_for_wrap:, adapter: Runtime::YieldAdapter, block:, id:, exec_context:, options_for_invoke_handler: {}, rows_after_invoke_handler: [])
        block_activity, outputs = Macro.block_activity_for(nil, exec_context: exec_context, &block)

        # DISCUSS: we're currently allowing structural parameters for Rescue().
        rows = [
          [:block_activity, node: Runtime::Node::BlockForYield[block_activity, Circuit::Processor]], # {:block_for_yield} is now in lib_ctx.
          [:invoke_handler, handler_for_wrap, adapter, options_for_invoke_handler], # this is where the user's code yields, and we run the {block_activity}.
          *rows_after_invoke_handler,
          [:translate_signal, Runtime.method(:translate_signal), merge_to_lib_ctx: {outputs: outputs}],
        ]

        wrap_circuit = Circuit::Builder.Pipeline(
          *rows
        )

        options_for_node = {
          outputs: outputs,
          id: id,
                                                                                        # FIXME: can we make a Activity::Scoped node, that does this automatically?
          node_for_call_task: Circuit::Node::Scoped[wrap_circuit, Circuit::Processor, copy_to_outer_ctx: [:target_ctx]], # TODO: test we do not leak anything.
        }

        return options_for_node
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

        class YieldAdapter
          def self.call(task, lib_ctx, flow_options, signal, **circuit_options)
            block = lib_ctx.fetch(:block_for_yield)

            task.(lib_ctx, flow_options, signal, **circuit_options, &block)
          end
        end

        class Node
          class BlockForYield < Circuit::Node
            def call(lib_ctx, flow_options, signal, **circuit_options) # DISCUSS: can we not do that at compile-time, somehow?
              block_for_yield = ->(*args, **kws) { super(*args, **kws) } # this is where the magic's happening. {super} will invoke the {block_activity}.

              return lib_ctx.merge(block_for_yield: block_for_yield), flow_options, signal
            end
          end
        end
      end

      module Helper
        def Wrap(handler_for_wrap, id: Macro.id_for(handler_for_wrap, macro: :Wrap), &block)
          return Macro::Wrap::Atom.new({handler_for_wrap: handler_for_wrap, block: block, id: id})
        end
      end
    end # Wrap
  end
end
