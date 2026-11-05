module Trailblazer
  module Macro
    module Each
      module Step
        def self.init(lib_ctx, flow_options, signal, target_ctx:, **)
          dataset = target_ctx.fetch(:dataset)

          return lib_ctx.merge(
            enumerator: dataset.each_with_index,
          ), flow_options, signal
        end

        def self.fetch_value_from_dataset(lib_ctx, flow_options, signal, enumerator:, **)
          value, index = enumerator.next

          return lib_ctx.merge(value: value, index: index), flow_options, "next"

        rescue StopIteration
          # DISCUSS: is there any other way to detect when an enumerator reached the end?
          return lib_ctx, flow_options, signal
        end
      end

      def self.options_for_dataset_from(dataset_from:)
        return {} unless dataset_from

        {
          Activity::Railway.Inject(:dataset, override: true) => dataset_from, # {ctx[:dataset]} is private to {each_activity}.
        }
      end

      module Helper
        # TODO: explain termini routing, Inject usage for "block activity", Out() => []
        #       BLOG: Each() is a perfect example of how versatile the TRB mechanics are

        # @api private The internals here are considered private and might change at some point.
        def Each(block_activity=nil, dataset_from: nil, item_key: :item, id: Macro.id_for(block_activity, macro: :Each, hint: dataset_from), collect: false, **variable_mapping_options_for_iterated, &block)
          exec_context = self.new # FIXME: how do we guarantee this is the OP?


          block_activity, outputs_from_block_activity = Trailblazer::Macro.block_activity_for(block_activity, exec_context: exec_context, &block)
          failing_termini_signals = outputs_from_block_activity.collect { |_, output| output.signal.is_a?(Activity::Terminus::Failure) ? output.signal : nil }.compact

          iterated_node = Circuit::Node::MergeToCircuitOptions[block_activity, Circuit::Processor,
            merge_to_circuit_options: {exec_context: exec_context}
          ]

          item_and_index_filter = Item_and_index_filterBuilder.new(item_key: item_key)

      options_for_each = {} # the top level Each thingy.

      collect_value_node_builder = {}
      if collect
        # "per iteration":
        collect_filter = ->(ctx, collected_from_each:, **) { {collected_from_each: collected_from_each += [ctx[:value]] } }
        collect_value_node_builder = {Activity::VariableMapping::DSL.Out() => collect_filter}

        options_for_each.merge!(Activity::Railway.Inject(:collected_from_each) => ->(*) { [] })
        options_for_each.merge!(Activity::Railway.Out() => [:collected_from_each])
      end

          in_node, out_node = Each.input_and_output_nodes_for_iterated(item_and_index_filter, collect_value_node_builder, variable_mapping_options_for_iterated)

          circuit = Circuit::Builder.Pipeline(
            [:init, Step.method(:init)],
            [:fetch_value_from_dataset, Step.method(:fetch_value_from_dataset),
              connections: Circuit::Resolver::Conditional.new(["next"], :vm_input, nil)
            ],
            [:vm_input, node: in_node],
            [:user_logic, node: iterated_node],
            [:vm_output, node: out_node, connections: Circuit::Resolver::Conditional.new(failing_termini_signals, nil, :fetch_value_from_dataset)], # DISCUSS: vmin/user_logic/vm_out could be separate, nested activity.
          )

          # TODO: explicit test that :value and :enumerator etc don't leak to the outside.
          each_node = Circuit::Node::Scoped[circuit, Circuit::Processor, copy_from_outer_ctx: [:target_ctx], copy_to_outer_ctx: [:target_ctx]]

          options_for_dataset_from = Each.options_for_dataset_from(dataset_from: dataset_from)

          options = {
            node_for_call_task: each_node,
            outputs: outputs_from_block_activity,
            id: id,
            **options_for_dataset_from,
            **options_for_each,
          }

          return options
        end

         # DSL options added to {block_activity} to implement {collect: true}.
        def self.options_for_collect(collect:)
          return {} unless collect

          {
            Activity::Railway.Inject(:collected_from_each) => ->(ctx, **) { [] }, # this is called only once.
            Activity::Railway.Out() => ->(ctx, collected_from_each:, **) { {collected_from_each: collected_from_each += [ctx[:value]] } }
          }
        end
      end

      # Mimick the i/o DSL for the iterated activity, and return the in and out nodes.
      def self.input_and_output_nodes_for_iterated(item_and_index_filter, collect_value_node_builder, variable_mapping_options_for_iterated)
        # TODO: we're mimicking the dsl gem here in order to get i/o. very error-prone and leaky. and (too?) much knowledge about öy.
        lib_ctx, _ = Activity::VariableMapping::DSL::Normalizer.disect_input_and_output({}, {}, nil,
          item_and_index_filter => nil, # acts like Inject().
          Activity::VariableMapping::DSL.Out() => [],
          **collect_value_node_builder,
          **variable_mapping_options_for_iterated
        )

        lib_ctx, _ = Activity::VariableMapping::DSL::Normalizer.convert_dsl_to_nodes({}, {}, nil,
          exec_context: self,
          **lib_ctx
        )

        return lib_ctx[:node_for_input], lib_ctx[:node_for_output]
      end

      Item_and_index_filterBuilder = Class.new(Activity::VariableMapping::DSL::Inject) do
        def initialize(item_key:)
          @item_key = item_key
        end

        def call(*) # This is called in {VM::Input.convert_tuples_to_node}.
          # A filter with circuit interface.
          index_provider_filter = ->(lib_ctx, flow_options, _, index:, **) { return lib_ctx, flow_options, index }
          value_provider_filter = ->(lib_ctx, flow_options, _, value:, **) { return lib_ctx, flow_options, value }

          index_node = Activity::VariableMapping::Runtime::Filter::Wrapped.build_node(
            provider_node: Circuit::Node[index_provider_filter, Circuit::Task::Adapter::LibInterface],
            id: :add_index,
            write_name: :index
          )

          item_node = Activity::VariableMapping::Runtime::Filter::Wrapped.build_node(
            provider_node: Circuit::Node[value_provider_filter, Circuit::Task::Adapter::LibInterface],
            id: :add_item,
            write_name: @item_key
          )

          return [
            ["each.in.index", node: index_node],
            ["each.in.item", node: item_node]
          ]
        end
      end
    end
  end

  # if const_defined?(:Developer) # FIXME: how do you properly check for a gem?
  #   Developer::Trace::Debugger.add_normalizer_step!(
  #     Macro::Each.method(:compute_runtime_id),
  #     id:     "Each.runtime_id",
  #     append: :runtime_id, # so that the following {#runtime_path} picks up those changes made here.
  #   )
  # end
end
