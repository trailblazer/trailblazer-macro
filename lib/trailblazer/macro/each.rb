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
        # module_function

        # TODO: explain termini routing, Inject usage for "block activity", Out() => []
        #       BLOG: Each() is a perfect example of how versatile the TRB mechanics are

        # @api private The internals here are considered private and might change at some point.
        def Each(block_activity=nil, dataset_from: nil, item_key: :item, id: Macro.id_for(block_activity, macro: :Each, hint: dataset_from), collect: false, **dsl_options_for_iterated, &block)
          exec_context = self.new # FIXME: how do we guarantee this is the OP?


          block_activity, outputs_from_block_activity = Trailblazer::Macro.block_activity_for(block_activity, exec_context: exec_context, &block)
          failing_termini_signals = outputs_from_block_activity.collect { |_, output| output.signal.is_a?(Activity::Terminus::Failure) ? output.signal : nil }.compact

# Developer.puts(block_activity.config.circuit)# if block


          iterated_node = Circuit::Node::MergeToCircuitOptions[block_activity, Circuit::Processor, merge_to_circuit_options: {
            exec_context: exec_context
          }]


# :index, :item
          my_custom_filter_with_wrap_hash = Class.new(Trailblazer::Activity::VariableMapping::Runtime::Filter) do
            def self.build_circuit(**)
              circuit = Trailblazer::Circuit::Adds.(super, Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH) # redundant to Override.
            end
          end

          provider_filter = ->(lib_ctx, flow_options, signal, index:, **) do
            return lib_ctx, flow_options, index
          end

          provider_node = Trailblazer::Circuit::Node[provider_filter, Trailblazer::Circuit::Task::Adapter::LibInterface]

          node_for_index = my_custom_filter_with_wrap_hash.build_node(
            provider_node: provider_node,
            id: :add_index,
            write_name: :index
          )

          provider_filter = ->(lib_ctx, flow_options, signal, value:, **) do
            return lib_ctx, flow_options, value
          end

          provider_node = Trailblazer::Circuit::Node[provider_filter, Trailblazer::Circuit::Task::Adapter::LibInterface]

          node_for_item = my_custom_filter_with_wrap_hash.build_node(
            provider_node: provider_node,
            id: :add_item,
            write_name: item_key
          )

# DISCUSS: so much knowledge about iternals of öy.
      # in_node = Activity::VariableMapping::Build::Input.([[:each_in, node: node_for_index], [:in_item, node: node_for_item]], add_default_ctx: true)


    my_left_tuple = ->(*) { [[:"each.in.item", node: node_for_item], [:"each.in.index", node: node_for_index]] }


      options_for_each = {} # the top level Each thingy.

      collect_value_node_builder = ->(*) { [] }
      if collect
      # "per iteration"
        collect_value_node_builder =
        ->(*) {
        [[:"each.out.collect_from_each", node: Activity::VariableMapping::Runtime::Filter.build_node(
          id: nil,
          args_for_step_build: [->(ctx, collected_from_each:, **) { {collected_from_each: collected_from_each += [ctx[:value]] } }, {}],
          # write_name: :my_slug,
        )]]
         }

        options_for_each.merge!(Activity::Railway.Inject(:collected_from_each) => ->(*) { [] })
        options_for_each.merge!(Activity::Railway.Out() => [:collected_from_each])
      end

raise "add dsl_options_for_iterated here!"
    lib_ctx, _ = Activity::VariableMapping::DSL::Normalizer.convert_dsl_to_nodes({}, {}, nil,
      ins: [
        # [dsl.In(), [:current_user]],
        [my_left_tuple]],
      outs: [[Activity::VariableMapping::DSL.Out(), []],
        collect_value_node_builder
      ],
      injects: [],
      default_ctx_for_input: true,
      default_ctx_for_output: false,

      exec_context: self,
    )

    in_node, out_node = lib_ctx[:node_for_input], lib_ctx[:node_for_output]




          circuit = Circuit::Builder.Pipeline(
            [:init, Step.method(:init)],
            [:fetch_value_from_dataset, Step.method(:fetch_value_from_dataset),
              connections: Circuit::Resolver::Conditional.new(["next"], :vm_input, nil)
            ],
            [:vm_input, node: in_node],
            [:user_logic, node: iterated_node],
            # [:vm_output, node: out_node, connections: Circuit::Resolver::Fixed.new(:fetch_value_from_dataset)],
            [:vm_output, node: out_node, connections: Circuit::Resolver::Conditional.new(failing_termini_signals, nil, :fetch_value_from_dataset)], # DISCUSS: vmin/user_logic/vm_out could be separate, nested activity.
          )

          # TODO: explicit test that :value and :enumerator etc don't leak to the outside.
          each_node = Circuit::Node::Scoped[circuit, Circuit::Processor, copy_from_outer_ctx: [:target_ctx], copy_to_outer_ctx: [:target_ctx]]



          # pp circuit
          # Developer.puts circuit




          options_for_dataset_from = Each.options_for_dataset_from(dataset_from: dataset_from)

          options = {
            # **Activity::Railway.Subprocess(block_activity),
            node_for_call_task: each_node,
            outputs: outputs_from_block_activity,
            # adapter: Cir,
            id: id,
            Out() => [],# per default, don't let anything out.
            **options_for_dataset_from,
            **options_for_each,
          }

          return options


          # DISCUSS: move to Wrap.
          # TODO: if a patched step in the iterated activity would add another teminus, this would be inconsistent.
          #       we'd have to recompute this via `inherited`.
            termini_instructions_from_block_activity =
              outputs_from_block_activity.
                # DISCUSS: End.success needs to be the last here, so it's directly behind {Start.default}.
                sort { |a,b| a.semantic == :success ? 1 : -1 }.
                collect { |output|
                  [:terminus, task: output.signal, id: "End.#{output.semantic}", magnetic_to: output.semantic, append_to: "Start.default"]
                }

          railway_options = Activity::Railway::DSL.options_for_initialize
          start_instruction = railway_options[:layout_instructions][0]

          layout_instructions = [
            start_instruction,
            *termini_instructions_from_block_activity
          ]

          each_activity = Trailblazer::Activity::Railway(layout_instructions: layout_instructions) do

            # TODO: make publicly configurable.
            @state.update!(:fields) do |fields|
              fields.merge(
                failing_semantics: [:failure, :fail_fast],
                each: true, # mark this activity for {compute_runtime_id}.
              )
            end

            step Subprocess(iterated_activity, strict: true),
                id: "iterated_block",
                Inject(:index, builder: index_filter_builder) => index_filter_builder,
                Inject(:item, builder: item_filter_builder) => item_filter_builder,
                Out() => [], # per default, don't let anything out.
                **Each.options_for_collect(collect: collect),
                **dsl_options_for_iterated
          end

          each_activity.class_eval do
            def self.call(ctx, flow_options, circuit_options)
              runner = circuit_options.fetch(:runner)

              # We don't really need to override/replace {circuit} as we only want to change the way it's run.
              iterated_railway = to_h[:circuit].to_h[:map].keys[1] # DISCUSS: maybe find by id?

              failing_semantics = @state.get(:fields).fetch(:failing_semantics)

              dataset = ctx.fetch(:dataset)
              signal  = iterated_railway.to_h[:outputs].find { |output| output.semantic == :success }.signal # FIXME: !!! do this at compile time and recompute when patched via {#inherited}.

              dataset.each_with_index do |item, index|

                each_options_for_iterated = {
                  index: index,
                  item: item,
                }

                # we "inject" item_key and index via Runner.(..., item_key => ..) and then the input filter grabs that.
                ctx, flow_options, signal = runner.(iterated_railway, ctx, flow_options, circuit_options.merge(activity: self, **each_options_for_iterated))

                # Break the loop if {iterated_activity} emits a failure signal.
                break if failing_semantics.include?(signal.to_h[:semantic]) # TODO: use generic check from older macro
              end

              return ctx, flow_options, signal
            end
          end

          options_for_dataset_from = Each.options_for_dataset_from(dataset_from: dataset_from)

          {
            **Trailblazer::Activity::Railway.Subprocess(each_activity),
            id: id,
            **options_for_dataset_from,
          }
        end

         # DSL options added to {block_activity} to implement {collect: true}.
        def self.options_for_collect(collect:)
          return {} unless collect

          {
            Activity::Railway.Inject(:collected_from_each) => ->(ctx, **) { [] }, # this is called only once.
            Activity::Railway.Out() => ->(ctx, collected_from_each:, **) { {collected_from_each: collected_from_each += [ctx[:value]] } }
          }
        end





        # Gets included in Debugger's Normalizer. Results in IDs like {invoke_block_activity.1}.
        def self.compute_runtime_id(ctx, flow_options, _, trace_node:, activity:, compile_id:, **)
          # activity is the iterated activity
          fields = activity.to_h[:fields]
          return ctx, flow_options unless fields && fields[:each] == true

          # Developer::Trace::Snapshot::Ctx.ctx_snapshot_for(trace_node.snapshot_before, .data
  # FIXME: BETTER API, we need access to stack now


          # index = trace_node.snapshot_before.data[:ctx_snapshot].fetch(:index)
          index = trace_node.snapshot_before.data[:ctx_variable_changeset].find { |name, version, value| name == :index }[2]

          ctx = ctx.merge(runtime_id: "#{compile_id}.#{index}")

          return ctx, flow_options
        end
      end
    end
  end

  if const_defined?(:Developer) # FIXME: how do you properly check for a gem?
    Developer::Trace::Debugger.add_normalizer_step!(
      Macro::Each.method(:compute_runtime_id),
      id:     "Each.runtime_id",
      append: :runtime_id, # so that the following {#runtime_path} picks up those changes made here.
    )
  end
end
