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
          decider_node = Activity::Step.build(decider, exec_context: exec_context, binary: false) # TODO: we could allow {:lib_interface}.

          options =
            if static.any?
              Nested.Static(decider_node, static: static)
            else
              Nested.Dynamic(decider_node)
            end

          return options.merge(id: id)
        end
      end
    end

    # @private
    # @api private The internals here are considered private and might change in the near future.
    #
    # We don't need to override {Strategy.call} here to prevent {:exec_context} from being changed.
    # The decider is run in the taskWrap before the {Nested} subclass is actually called.
    class Nested# < Trailblazer::Activity::Railway
      # Dynamic is without static where we don't even know what *could* be the actual
      # nested activity until it's runtime.
      def self.Dynamic(decider_node)
        node = Circuit::Builder.Node(
          [:decider, node: decider_node],
          [:invoke_dynamic_activity, node: Dynamic::Node.new]
        )

        {
          node_for_call_task: node,
          outputs: Activity::FastTrack.to_h[:outputs] # we don't have to map "thanks" to Struct's #eql behavior. (just being lazy right there)
        }
      end

      class Dynamic
        class Node# < Circuit::Node
          def call(lib_ctx, flow_options, decision, **circuit_options)
            # super(lib_ctx, flow_options, nil, **circuit_options, node: decision)
            node = Circuit::Node[decision, Circuit::Processor]
            node.(lib_ctx, flow_options, nil, **circuit_options) # FIXME: maybe we can find another way, this is tedious.
          end
        end
      end

      # Code to handle [:static]. This is called "static" as you configure the possible activities at
      # compile-time. This is the recommended way.
      #
      # TODO: allow configuring Output of Nested per internal nested activity, e.g.
      #         step Nested(.., Id3Tag => {Output(:invalid_metadata) => ...}
      #       this will help when semantics overlap.
      def self.Static(decider_node, static:)
        # Some mapping work necessary for the signals we return.
        id_2_activity = static.collect { |activity| [activity.to_s.to_sym , activity]  }

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

        return {node_for_call_task: node, outputs: public_outputs}
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
