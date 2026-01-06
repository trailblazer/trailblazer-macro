module Trailblazer
  module Macro
    # TODO: {user_wrap}: rename to {wrap_handler}.
    def self.Wrap(user_wrap, id: Macro.id_for(user_wrap, macro: :Wrap), &block)
      user_wrap = Wrap::Deprecate.deprecate_user_handler_with_old_circuit_interface(user_wrap)

      block_activity, outputs = Macro.block_activity_for(nil, &block)

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

    # Wrap exposes {#inherited} which will also copy the block activity.
    # Currently, this is only used for patching (as it will try to subclass Wrap).
    class Wrap < Macro::Strategy
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

      # Remove in 2.3.
      module Deprecate
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
              ctx, flow_options, signal = block.(*args) # Run the wrapped activity.

              return signal, [ctx, flow_options] # Return the old style circuit interface.
            end

            # Translate from new positional circuit interface to the old, clumsy one.
            signal, (ctx, flow_options) = user_handler.([ctx, flow_options], **circuit_options, &block_returning_old_array_style)

            return ctx, flow_options, signal
          end

          return deprecated_user_handler_adapter
        end

        def self.deprecate_yield_without_args(block_activity, ctx, flow_options, circuit_options)
          ->(*args) do
            if args.size == 0 # {yield} old style, deprecated.
              Activity::Deprecate.warn(
                Activity::DSL::Linear::Deprecate.dsl_caller_location(index: 2),
                  %(When using `yield` in Wrap(), please pass through the three "circuit interface" arguments, see # FIXME ------------------------)
              )

              return BLOCK_FOR_YIELD.(block_activity, ctx, flow_options, circuit_options) # pass the circuit interface args into the block_activity invocation manually.
            end

            BLOCK_FOR_YIELD.(block_activity, *args) # pass the "real", procedurally passed args into the block_activity invocation.
          end
        end
      end
    end # Wrap
  end
end
