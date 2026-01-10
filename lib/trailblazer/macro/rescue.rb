module Trailblazer
  module Macro
    NoopHandler = lambda { |ctx, flow_options, circuit_options, exception:| }

    def self.Rescue(*exceptions, handler: NoopHandler, id: Macro.id_for(nil, macro: :Rescue), &block)
      exceptions = [StandardError] unless exceptions.any?

      # In Rescue(), for whatever reason we support a circuit interface handler
      # where we ignore the result set?
      # handler    = Trailblazer::Activity::Circuit.Step(handler)

      is_instance_method = false
      handler = Activity::Option.build(handler) do |instance_method|
        # this is for :instance_methods
        is_instance_method = true
        callable = Rescue::InstanceMethodWithCircuitInterfaceAndKwargs.new(instance_method)

        # assuming we have to deprecate everything.
        Rescue::Deprecate::InstanceMethodAtRuntime.new(callable, instance_method) # TODO: remove in 2.3.
      end

      if is_instance_method
        # deprecate at runtime :D
      else
        # deprecate now!
        if handler.method(:call).arity == -3
          # raise handler.inspect
          puts "@@@@@ xxx #{handler.inspect}"
          Rescue::Deprecate.warning_for_deprecated_callable
# raise "why are we not hitting this from line 291?"
          handler = Rescue::Deprecate::Callable.new(handler)
        end
      end


      # every handler is called identically, no matter if it's a callable or an :instance_method.
      # the idea is we do NOT have to know that and can always call CI/extended circuit interface (with kwargs)
      # the other idea is that we have to wrap as little as possible, and :instance_method is a special case (not edge case, though).
      # handler.(ctx, flow_options, circuit_options, exception: exception)




      # This block is evaluated by {Wrap}.
      rescue_block = ->(ctx, flow_options, circuit_options, &nested_activity) do
        begin
          nested_activity.call(ctx, flow_options, circuit_options) # FIXME: use yield.
        rescue *exceptions => exception
          # DISCUSS: should we deprecate this signature and rather apply the Task API here?
          # handler.call(exception, ctx, flow_options, circuit_options) # FIXME: when there's an error here, it shows the wrong exception!
          handler.call(ctx, flow_options, circuit_options, exception: exception) # FIXME: when there's an error here, it shows the wrong exception!

          return ctx, flow_options, Trailblazer::Activity::Left
        end
      end

      Wrap(rescue_block, id: id, &block)
    end

    module Rescue
      module Deprecate
        class InstanceMethodAtRuntime < Struct.new(:filter, :instance_method_option)
          def call(ctx, flow_options, circuit_options, exception:)
            exec_context = circuit_options.fetch(:exec_context)
            # hacky, but hey, it's deprecation code!
            instance_method = exec_context.method(instance_method_option.instance_variable_get(:@filter))

            if instance_method.arity == -3 # this doesn't catch all, but we ignore that.
              # Activity::Deprecate.warn(
                # Activity::DSL::Linear::Deprecate.dsl_caller_location(after: /forwardable.+Rescue/),
              warning =  "#{exec_context.class}##{instance_method.name} " + Deprecate.message_for_deprecation_warning

              Kernel.warn %([Trailblazer] #{warning}\n) # TODO: allow that in Activity::Deprecate.
            end

            filter.(ctx, flow_options, circuit_options, exception: exception)
          end
        end

        class Callable < Struct.new(:filter)
          def call(ctx, flow_options, circuit_options, exception:)
            # Call a user handler with the deprecated interface.
            filter.(exception, [ctx, flow_options], **circuit_options)
          end
        end

        def self.message_for_deprecation_warning
          %(The Rescue() handler has a new interface, the old `(exception, (ctx), ..), **` signature is deprecated.
Please use (ctx, flow_options, circuit_options, exception:, **) , check ### FIXME _____---------------)
        end

        def self.warning_for_deprecated_callable
          Activity::Deprecate.warn(
            Activity::DSL::Linear::Deprecate.dsl_caller_location(after: /forwardable.+Rescue/),
            message_for_deprecation_warning
          )
        end
      end
      # This is kind of specific to Rescue, but might be useful elsewhere. We want to run a circuit interface
      # *instance method* with keyword arguments. in a normal CI-conform callable, this doesn't need any
      # wrapping, but instance_methods are different.
      class InstanceMethodWithCircuitInterfaceAndKwargs < Struct.new(:instance_method_option) # DISCUSS: move somewhere else?
        def call(ctx, flow_options, circuit_options, exception:, **kwargs)
          # Call the method the old, weird style with exception as a positional argument
          # followed by the composite circuit interface.
          instance_method_option.(exception, [ctx, flow_options], keyword_arguments: kwargs, **circuit_options)
        end
      end
    end
  end
end

# TODO: add docs test with File.read step that fails (easier to understand)
