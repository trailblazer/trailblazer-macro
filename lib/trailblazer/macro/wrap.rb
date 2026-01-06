module Trailblazer
  module Macro
    # TODO: {user_wrap}: rename to {wrap_handler}.
    def self.Wrap(user_wrap, id: Macro.id_for(user_wrap, macro: :Wrap), &block)
      user_wrap = Wrap::Deprecated.deprecate_user_handler_with_old_circuit_interface(user_wrap)

      block_activity, outputs = Macro.block_activity_for(nil, &block)

      outputs   = Hash[outputs.collect { |output| [output.semantic, output] }] # FIXME: redundant to Subprocess().

      # Since in the user block, you can return Railway.pass! etc, we need to map
      # those to the actual wrapped block_activity's end.
      signal_to_output = {
        Activity::Right               => outputs[:success].signal,
        Activity::Left                => outputs[:failure].signal,
        Activity::FastTrack::PassFast => outputs[:pass_fast].signal,
        Activity::FastTrack::FailFast => outputs[:fail_fast].signal,
        true               => outputs[:success].signal,
        false              => outputs[:failure].signal,
        nil                => outputs[:failure].signal,
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

    # Wrap exposes {#inherited} which will also copy the block activity.
    # Currently, this is only used for patching (as it will try to subclass Wrap).
    class Wrap < Macro::Strategy
      def self.call(ctx, flow_options, circuit_options)
        # since yield is called without arguments, we need to pull default params from here. Oh ... tricky.

        block_called_from_user_yield = ->() { # DISCUSS: because we allow users to call {yield}, we don't receive any args here.
          Activity::Circuit::Runner.(block_activity, ctx, flow_options, circuit_options)
        }

        # call the user's Wrap {} block in the operation.
        # This will invoke block_called_from_user_yield above if the user block yields.
        user_handler = @state.get(:user_wrap)

        # Invoke the user's handler.
        returned = user_handler.(ctx, flow_options, circuit_options, &block_called_from_user_yield)

        # {returned} can be
        #   1. {circuit interface return} from the begin block, because the wrapped OP passed
        #   2. {task interface return} because the user block returns "customized" signals, true of fale

        if returned.is_a?(Array) # 1. {circuit interface return}, new style.
          ctx, flow_options, signal = returned
        else                     # 2. {task interface return}, only a signal (or true/false)
          # TODO: deprecate this?
          signal = returned
        end

        # If there's no mapping, use the original {signal} .
        # This usually means signal is a terminus or a custom signal.
        signal = @state.get(:signal_to_output).fetch(signal, signal)

        return ctx, flow_options, signal
      end

      # Remove in 2.3.
      module Deprecated
        # Wraps user handlers with a {(ctx, flow_options), **circuit_options} interface and
        # prints a deprecation warning.
        def self.deprecate_user_handler_with_old_circuit_interface(user_handler)
          arity = user_handler.is_a?(Proc) || user_handler.is_a?(Method) ? user_handler.arity : user_handler.method(:call).arity

          return user_handler if arity == 3 # new interface, {ctx, flow_options, circuit_options}

          Activity::Deprecate.warn(
            Activity::DSL::Linear::Deprecate.dsl_caller_location(index: 3),
            %(Handlers for Wrap() and Rescue() have a new interface, the old `(ctx, flow_options), **` signature and the return set is deprecated.
Please use the new positional circuit interface, check ### FIXME _____---------------
Do not forget to change the return set, too: `return <signal>, [ctx, flow_options]´ ==> `return ctx, flow_options, signal`)
          ) # TODO: also mention the yield change!

          deprecated_user_handler_adapter = ->(ctx, flow_options, circuit_options, &block) do
            block_returning_old_array_style = ->(*args) do # This is yielded by the user.
              ctx, flow_options, signal = block.(*args)

              return signal, [ctx, flow_options]
            end

            # Translate from new positional circuit interface to the old, clumsy one.
            signal, (ctx, flow_options) = user_handler.([ctx, flow_options], **circuit_options, &block_returning_old_array_style)

            return ctx, flow_options, signal
          end

          return deprecated_user_handler_adapter
        end
      end
    end # Wrap
  end
end
