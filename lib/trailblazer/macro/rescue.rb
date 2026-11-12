module Trailblazer
  module Macro
    NoopHandler = lambda { |lib_ctx, flow_options, *| return lib_ctx, flow_options, Activity::Left }

    module Rescue
      class Atom < DSL::Atom
        def build_node(exceptions:, handler:, id:, lib_interface:, exec_context:, **options)
          node_for_rescue_handler =
            if lib_interface
              Circuit::Node[handler, Circuit::Task::Adapter::LibInterface]
            else
              in_node, out_node = input_and_output_nodes_for_rescue_handler

              circuit = Circuit::Builder.Pipeline(
                [:in, node: in_node],
                [:handler, node: Activity::Step.build(handler, binary: true, exec_context: exec_context)],
                [:out, node: out_node],
              )

              Circuit::Node[circuit, Circuit::Processor]
            end

          exceptions = [StandardError] unless exceptions.any?

          wrap_options = Wrap.build_node(handler_for_wrap: Runtime.new(exceptions), id: id, exec_context: exec_context, **options)

          node = wrap_options[:node_for_call_task]
          circuit = node.task

          new_resolver_for_invoke_handler = Circuit::Resolver::Conditional.new([Runtime::Rescued], :handle_rescue, :translate_signal)
          circuit = Circuit::Adds.(circuit,
            [:handle_rescue, node_for_rescue_handler, :before, :translate_signal],
            [:invoke_handler, circuit.nodes[:invoke_handler], :replace, :invoke_handler, resolver: new_resolver_for_invoke_handler],
          ) # DISCUSS: patch? grabbing the original invoke_handler node is a contract breach.

          return wrap_options.merge(
            node_for_call_task: node.class[circuit, node.interface, copy_to_outer_ctx: node.copy_to_outer_ctx] # FIXME: better way to "clonstumize" node
          )
        end

        # FIXME: better API in vm.
        def input_and_output_nodes_for_rescue_handler()
          custom_inject = Class.new(Activity::VariableMapping::DSL::Inject) do
            def call(*) # This is called in {VM::Input.convert_tuples_to_node}.
              # A filter with circuit interface.
              provider_filter = ->(lib_ctx, flow_options, _, exception:, **) { return lib_ctx, flow_options, exception }

              inject_node = Activity::VariableMapping::Runtime::Filter::Wrapped.build_node(
                provider_node: Circuit::Node[provider_filter, Circuit::Task::Adapter::LibInterface],
                id: :inject_exception,
                write_name: :exception
              )

              return [
                ["rescue.inject.exception", node: inject_node],
              ]
            end
          end.new


          # TODO: we're mimicking the dsl gem here in order to get i/o. very error-prone and leaky. and (too?) much knowledge about öy.
          lib_ctx, _ = Activity::VariableMapping::DSL::Normalizer.disect_input_and_output({}, {}, nil,
            custom_inject => nil, # acts like Inject().
            # Activity::VariableMapping::DSL.Out() => [],
            # **collect_value_node_builder,
            # **variable_mapping_options_for_iterated
          )

          lib_ctx, _ = Activity::VariableMapping::DSL::Normalizer.convert_dsl_to_nodes({}, {}, nil,
            exec_context: self,
            **lib_ctx
          )

          return lib_ctx[:node_for_input], lib_ctx[:node_for_output]
        end
      end
      module Helper
        def Rescue(*exceptions, handler: NoopHandler, lib_interface: false, id: Macro.id_for(nil, macro: :Rescue), &block)
          lib_interface = true if handler == NoopHandler

          return Atom.new({exceptions: exceptions, handler: handler, id: id, block: block, lib_interface: lib_interface})
        end
      end

      class Runtime < Struct.new(:exceptions)
        Rescued = Class.new

        def call(lib_ctx, flow_options, signal, **circuit_options, &block)
          begin
            return yield(lib_ctx, flow_options, signal, **circuit_options)
          rescue *exceptions => exception
            # puts "exception"
            return lib_ctx.merge(exception: exception), flow_options, Rescued
          end
        end
      end
    end # Rescue
  end
end

# TODO: add docs test with File.read step that fails (easier to understand)
