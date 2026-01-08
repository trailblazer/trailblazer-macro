module Trailblazer
  module Macro
    NoopHandler = lambda { |*| }

    def self.Rescue(*exceptions, handler: NoopHandler, id: Macro.id_for(nil, macro: :Rescue), &block)
      exceptions = [StandardError] unless exceptions.any?

      # In Rescue(), for whatever reason we support a circuit interface handler
      # where we ignore the result set?
      # handler    = Trailblazer::Activity::Circuit.Step(handler)

      is_instance_method = false
      handler = Activity::Option.build(handler) do |instance_method|
        # this is for :instance_methods
        is_instance_method = true
        Rescue::InstanceMethodWithCircuitInterfaceAndKwargs.new(instance_method)
      end

      if is_instance_method
        # raise handler.inspect
        # deprecate at runtime :D
      else
        # deprecate now!
      end


      # every handler is called identically, no matter if it's a callable or an :instance_method.
      # the idea is we do NOT have to know that and can always call CI/extended circuit interface (with kwargs)
      # the other idea is that we have to wrap as little as possible, and :instance_method is a special case (not edge case, though).
      # handler.(ctx, flow_options, circuit_options, exception: exception)




      # This block is evaluated by {Wrap}.
      rescue_block = ->(ctx, flow_options, circuit_options, &nested_activity) do
        begin
          nested_activity.call # FIXME: use yield.
        rescue *exceptions => exception
          # DISCUSS: should we deprecate this signature and rather apply the Task API here?
          # handler.call(exception, ctx, flow_options, circuit_options) # FIXME: when there's an error here, it shows the wrong exception!
          handler.call(exception, ctx, flow_options, circuit_options) # FIXME: when there's an error here, it shows the wrong exception!

          return ctx, flow_options, Trailblazer::Activity::Left
        end
      end

      Wrap(rescue_block, id: id, &block)
    end

    module Rescue
      # This is kind of specific to Rescue, but might be useful elsewhere. We want to run a circuit interface
      # *instance method* with keyword arguments. in a normal CI-conform callable, this doesn't need any
      # wrapping, but instance_methods are different.
      class InstanceMethodWithCircuitInterfaceAndKwargs < Struct.new(:instance_method_option) # DISCUSS: move somewhere else?
        def call(ctx, flow_options, circuit_options, **kwargs)
          instance_method_option.(ctx, flow_options, circuit_options, keyword_arguments: kwargs, **circuit_options)
        end
      end
    end
  end
end

# TODO: add docs test with File.read step that fails (easier to understand)
