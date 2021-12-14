require 'securerandom'

module Trailblazer
  module Macro
    def self.Wrap(user_wrap, id: "Wrap/#{SecureRandom.hex(4)}", &block)
      activity = Class.new(Activity::FastTrack, &block) # This is currently coupled to {dsl-linear}.

      outputs  = activity.to_h[:outputs]
      outputs  = Hash[outputs.collect { |output| [output.semantic, output] }] # TODO: make that a helper somewhere.

      wrapped  = Wrap::Wrapped.new(activity, user_wrap, outputs)

      {task: wrapped, id: id, outputs: outputs}
    end

    module Wrap
      # behaves like an operation so it plays with Nested and simply calls the operation in the user-provided block.
      class Wrapped
        def initialize(operation, user_wrap, outputs)
          user_wrap = deprecate_positional_wrap_signature(user_wrap)

          @operation  = operation
          @user_wrap  = user_wrap

          # Since in the user block, you can return Railway.pass! etc, we need to map
          # those to the actual wrapped operation's end.
          @signal_to_output = {
            Operation::Railway.pass!      => outputs[:success].signal,
            Operation::Railway.fail!      => outputs[:failure].signal,
            Operation::Railway.pass_fast! => outputs[:pass_fast].signal,
            Operation::Railway.fail_fast! => outputs[:fail_fast].signal,
            true               => outputs[:success].signal,
            false              => outputs[:failure].signal,
            nil                => outputs[:failure].signal,
          }
        end

        def call((ctx, flow_options), **circuit_options)
          block_calling_wrapped = -> {
            call_wrapped_activity([ctx, flow_options], **circuit_options)
          }

          # call the user's Wrap {} block in the operation.
          # This will invoke block_calling_wrapped above if the user block yields.
          returned = @user_wrap.([ctx, flow_options], **circuit_options, &block_calling_wrapped)

          # {returned} can be
          #   1. {circuit interface return} from the begin block, because the wrapped OP passed
          #   2. {task interface return} because the user block returns "customized" signals, true of fale

          if returned.is_a?(Array) # 1. {circuit interface return}, new style.
            signal, (ctx, flow_options) = returned
          else                     # 2. {task interface return}, only a signal (or true/false)
            # TODO: deprecate this?
            signal = returned
          end

          # Use the original {signal} if there's no mapping.
          # This usually means signal is an End instance or a custom signal.
          signal = @signal_to_output.fetch(signal, signal)

          return signal, [ctx, flow_options]
        end

        def call_wrapped_activity((ctx, flow_options), **circuit_options)
          @operation.to_h[:activity].([ctx, flow_options], **circuit_options) # :exec_context is this instance.
        end

        private

        def deprecate_positional_wrap_signature(user_wrap)
          parameters = user_wrap.is_a?(Module) ? user_wrap.method(:call).parameters : user_wrap.parameters

          return user_wrap if parameters[0] == [:req] # means ((ctx, flow_options), *, &block), "new style"

          ->((ctx, _flow_options), **_circuit_options, &block) do
            warn "[Trailblazer] Wrap handlers have a new signature: ((ctx), *, &block)"
            user_wrap.(ctx, &block)
          end
        end
      end
    end # Wrap
  end
end
