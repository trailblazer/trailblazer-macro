require 'securerandom'

module Trailblazer
  module Macro
    # TODO: {user_wrap}: rename to {wrap_handler}.

    def self.Wrap(user_wrap, id: "Wrap/#{SecureRandom.hex(4)}", &block)
      block_activity, outputs = Macro.block_activity_for(nil, &block)

      outputs   = Hash[outputs.collect { |output| [output.semantic, output] }] # FIXME: redundant to Subprocess().

      task      = Wrap::Wrapped.new(block_activity, user_wrap, outputs)

      {
        task:     task,
        id:       id,
        outputs:  outputs,
      }
    end

    module Wrap
      # behaves like an operation so it plays with Nested and simply calls the operation in the user-provided block.
      class Wrapped
        private def deprecate_positional_wrap_signature(user_wrap)
          parameters = user_wrap.is_a?(Proc) || user_wrap.is_a?(Method) ? user_wrap.parameters : user_wrap.method(:call).parameters

          return user_wrap if parameters[0] == [:req] # means ((ctx, flow_options), *, &block), "new style"

          ->((ctx, flow_options), **circuit_options, &block) do
            warn "[Trailblazer] Wrap handlers have a new signature: ((ctx), *, &block)"
            user_wrap.(ctx, &block)
          end
        end

        def initialize(block_activity, user_wrap, outputs)
          user_wrap = deprecate_positional_wrap_signature(user_wrap)

          @block_activity   = block_activity
          @user_wrap        = user_wrap

          # Since in the user block, you can return Railway.pass! etc, we need to map
          # those to the actual wrapped block_activity's end.
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
          # since yield is called without arguments, we need to pull default params from here. Oh ... tricky.
          block_calling_wrapped = ->(args=[ctx, flow_options], kwargs=circuit_options) {
            Activity::Circuit::Runner.(@block_activity, args, **kwargs)
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

      end
    end # Wrap
  end
end
