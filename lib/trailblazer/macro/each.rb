module Trailblazer
  module Macro
    # TODO: explain termini routing, Inject usage for "block activity", Out() => []
    #       BLOG: Each() is a perfect example of how versatile the TRB mechanics are

    # @api private The internals here are considered private and might change at some point.
    def self.Each(block_activity=nil, dataset_from: nil, item_key: :item, id: Macro.id_for(block_activity, macro: :Each, hint: dataset_from), collect: false, **dsl_options_for_iterated, &block)
      # TODO: 2.5. fix
      dsl_options_for_iterated = block_activity if block_activity.is_a?(Hash) # Ruby 2.5 and 2.6

      iterated_activity, outputs_from_block_activity = Trailblazer::Macro.block_activity_for(block_activity, &block)
      iterated_activity.extend(Trailblazer::Macro::Each::Transitive) unless block_activity # DISCUSS: do this in {#block_activity_for}?

      # filter to set ctx[:index]
      # The interesting part here is that we read dynamic values from the {circuit_options}, to not
      # pollute the business ctx.
      index_filter = ->(ctx, flow_options, circuit_options) {
        value     = circuit_options.fetch(:index)

        return ctx, flow_options, value
      }

      index_filter_builder = ->(right_option, **) {
        pipe_task = Activity::DSL::Linear::VariableMapping::Runtime::FilterStep.build(write_name: :index, filter: index_filter, wrap_value_with_hash: true)

        [
          [
            pipe_task,
            id: "each.index",
            prepend: "input.scope"
          ]
        ]
      }

      item_filter = ->(ctx, flow_options, circuit_options) {
        value     = circuit_options.fetch(:item)

        return ctx, flow_options, value
      }

      item_filter_builder = ->(right_option, **) {
        pipe_task = Activity::DSL::Linear::VariableMapping::Runtime::FilterStep.build(write_name: item_key, filter: item_filter, wrap_value_with_hash: true)

        [
          [
            pipe_task,
            id: "each.item",
            prepend: "input.scope"
          ]
        ]
      }

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

    class Each < Macro::Strategy
      # FIXME: for Strategy that wants to pass-through the {:exec_context}, so it
      # looks "invisible" for steps.
      module Transitive
        def call(ctx, flow_options, circuit_options)
          exec_context = circuit_options.fetch(:exec_context) # FIXME: not needed.

          # exec_context is our hosting Song::Activity::Cover
          to_h[:activity].call(ctx, flow_options, circuit_options)
        end
      end

       # DSL options added to {block_activity} to implement {collect: true}.
      def self.options_for_collect(collect:)
        return {} unless collect

        {
          Activity::Railway.Inject(:collected_from_each) => ->(ctx, **) { [] }, # this is called only once.
          Activity::Railway.Out() => ->(ctx, collected_from_each:, **) { {collected_from_each: collected_from_each += [ctx[:value]] } }
        }
      end

      def self.options_for_dataset_from(dataset_from:)
        return {} unless dataset_from

        {
          Activity::Railway.Inject(:dataset, override: true) => dataset_from, # {ctx[:dataset]} is private to {each_activity}.
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

  if const_defined?(:Developer) # FIXME: how do you properly check for a gem?
    Developer::Trace::Debugger.add_normalizer_step!(
      Macro::Each.method(:compute_runtime_id),
      id:     "Each.runtime_id",
      append: :runtime_id, # so that the following {#runtime_path} picks up those changes made here.
    )
  end
end
