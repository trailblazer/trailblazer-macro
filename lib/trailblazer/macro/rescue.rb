module Trailblazer
  module Macro
    NoopHandler = ->(*) {}

    # noinspection RubyClassMethodNamingConvention
    def self.Rescue(*exceptions, handler: NoopHandler, &block)
      exceptions = [StandardError] unless exceptions.any?

      handler    = Rescue.deprecate_positional_handler_signature(handler)
      handler    = Trailblazer::Option(handler)

      # This block is evaluated by {Wrap}.
      rescue_block = ->((ctx, flow_options), **circuit_options, &nested_activity) do
        begin
          nested_activity.call
        rescue *exceptions => exception
          # DISCUSS: should we deprecate this signature and rather apply the Task API here?
          handler.call(exception, ctx, **circuit_options) # FIXME: when there's an error here, it shows the wrong exception!

          [Operation::Railway.fail!, [ctx, flow_options]]
        end
      end

      Wrap(rescue_block, id: "Rescue(#{SecureRandom.hex(4)})", &block)
      # FIXME: name
      # [ step, name: "Rescue:#{block.source_location.last}" ]
    end

    # TODO: remove me in 2.2.
    module Rescue
      def self.deprecate_positional_handler_signature(handler)
        return handler if handler.is_a?(Symbol) # can't do nothing about this.
        return handler if handler.method(:call).arity != 2 # means (exception, (ctx, flow_options), *, &block), "new style"

        ->(exception, (ctx, _flow_options), **_circuit_options, &block) do
          warn "[Trailblazer] Rescue handlers have a new signature: (exception, *, &block)"
          handler.(exception, ctx, &block)
        end
      end
    end
  end
end
