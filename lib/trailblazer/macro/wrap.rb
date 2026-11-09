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

        options_for_node = {
          Activity::Railway.Output(:failure_from_wrap_handler, signal: Activity::Left) => Activity::Railway.Track(:failure),
          Activity::Railway.Output(:success_from_wrap_handler, signal: Activity::Right) => Activity::Railway.Track(:success), # TODO: test this explicitly, return it from the handler.
          outputs: outputs,
          id: id,
          node_for_call_task: Wrap::Node[block_activity, Circuit::Processor, options: {handler_for_wrap: handler_for_wrap}]
        }

        return options_for_node
      end

      module Helper
        def Wrap(handler_for_wrap, id: Macro.id_for(handler_for_wrap, macro: :Wrap), &block)
          return Macro::Wrap::Atom.new({handler_for_wrap: handler_for_wrap, block: block, id: id})

          outputs   = Hash[outputs.collect { |output| [output.semantic, output] }] # FIXME: redundant to Subprocess().

          # Since in the user block, you can return Railway.pass! etc, we need to translate
          # those to the actual block_activity's termini.
          signal_to_output = {
            Activity::Right               => outputs[:success].signal,
            Activity::Left                => outputs[:failure].signal,
            Activity::FastTrack::PassFast => outputs[:pass_fast].signal,
            Activity::FastTrack::FailFast => outputs[:fail_fast].signal,
          }

          state = Declarative::State(
            # this is important, so we subclass the actually wrapped activity when {Wrap} is subclassed.
            block_activity:   [block_activity, {copy: Trailblazer::Declarative::State.method(:subclass)}],
            user_wrap:        [user_wrap, {}], # DISCUSS: we could even allow the wrap_handler to be patchable.
            signal_to_output: [signal_to_output, {}],
          )

          task = Class.new(Wrap) do
            extend Macro::Strategy::State # now, the Wrap subclass can inherit its state and copy the {block_activity}.
            initialize!(state)
          end
          # DISCUSS: unfortunately, Ruby doesn't allow to set this during {Class.new}.

          {
            task:     task,
            id:       id,
            outputs:  outputs,
          }
        end

      end

      class Node < Circuit::Node
        def call(lib_ctx, flow_options, signal, **circuit_options)
          handler_for_wrap = options.fetch(:handler_for_wrap)

          block_for_yield = ->(*args) { interface.(task, lib_ctx, flow_options, signal, **circuit_options) }

          handler_for_wrap.(lib_ctx, flow_options, signal, **circuit_options, &block_for_yield)
        end
      end
    end
    # TODO: {user_wrap}: rename to {wrap_handler}.

    # Wrap exposes {#inherited} which will also copy the block activity.
    # Currently, this is only used for patching (as it will try to subclass Wrap).
    class Wrap_ < Macro::Strategy

      # This block is invoked in the user handler when calling {yield(ctx, flow_options, circuit_options)}.
      BLOCK_FOR_YIELD = ->(block_activity, ctx, flow_options, circuit_options) {
        Activity::Circuit::Runner.(block_activity, ctx, flow_options, circuit_options)
      }

      def self.call(ctx, flow_options, circuit_options)
        # since yield is called without arguments, we need to pull default params from here. Oh ... tricky.
        # TODO: in 2.3, replace this with
        #         block_called_from_user_yield = BLOCK_FOR_YIELD
        # We have to create a proc at runtime, unfortunately, since we need ctx and friends.
        block_called_from_user_yield = Deprecate.deprecate_yield_without_args(block_activity, ctx, flow_options, circuit_options)

        user_handler = @state.get(:user_wrap)

        # Invoke the user's handler.
        ctx, flow_options, signal = user_handler.(ctx, flow_options, circuit_options, &block_called_from_user_yield)

        # The user handler is allowed to return signals like Right and Left. We need to translate
        # those to termini signals from the block_activity, cause those are the only ones
        # we route.
        # DISCUSS: i would love to skip this, but that'd mean the user has to return a
        #          "native" signal from their block.
        signal = @state.get(:signal_to_output).fetch(signal, signal)

        return ctx, flow_options, signal
      end
    end # Wrap
  end
end
