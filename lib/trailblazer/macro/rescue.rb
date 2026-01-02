module Trailblazer
  module Macro
    NoopHandler = lambda { |*| }

    def self.Rescue(*exceptions, handler: NoopHandler, id: Macro.id_for(nil, macro: :Rescue), &block)
      exceptions = [StandardError] unless exceptions.any?

      handler    = Trailblazer::Activity::Circuit.Step(handler)

      # This block is evaluated by {Wrap}.
      rescue_block = ->((ctx, flow_options), **circuit_options, &nested_activity) do
        begin
          nested_activity.call
        rescue *exceptions => exception
          # DISCUSS: should we deprecate this signature and rather apply the Task API here?
          handler.call(exception, ctx, flow_options, circuit_options) # FIXME: when there's an error here, it shows the wrong exception!

          return ctx, flow_options, Operation::Railway.fail!
        end
      end

      Wrap(rescue_block, id: id, &block)
    end
  end
end
