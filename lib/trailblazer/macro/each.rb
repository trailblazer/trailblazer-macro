module Trailblazer
  module Macro
    class Each < Macro::Strategy
      # FIXME: for Strategy that wants to pass-through the exec_context, so it
      # looks "invisible" for steps.
      module Transitive
        def call(args, exec_context:, **circuit_options)
          # exec_context is our hosting Song::Activity::Cover
          to_h[:activity].call(args, exec_context: exec_context, **circuit_options)
        end
      end

      def self.call((ctx, flow_options), runner:, **circuit_options) # DISCUSS: do we need {start_task}?
        dataset           = ctx.fetch(:dataset)
        signal            = @state.get(:success_signal)
        item_key          = @state.get(:item_key)
        failing_semantic  = @state.get(:failing_semantic)
        activity          = @state.get(:activity)

        # I'd like to use {collect} but we can't {break} without losing the last iteration's result.
        dataset.each_with_index do |element, index|
          # This new {inner_ctx} will be disposed of after invoking the item activity.
          inner_ctx = ctx.merge(
            item_key => element, # defaults to {:item}
            :index   => index,
          )

          # TODO: test aliasing
          wrap_ctx, _ = ITERATION_INPUT_PIPE.({aggregate: {}, original_ctx: inner_ctx}, [[ctx, flow_options], circuit_options])
          inner_ctx   = wrap_ctx[:input_ctx]

          # using this runner will make it look as if block_activity is being run consequetively within {Each.iterate} as if they were steps
          # Use TaskWrap::Runner to run the each block. This doesn't create the container_activity
          # and literally simply invokes {block_activity.call}, which will set its own {wrap_static}.
          signal, (returned_ctx, flow_options) = runner.(
            block_activity,
            [inner_ctx, flow_options],
            runner:   runner,
            **circuit_options,
            activity: activity,
          )

          # {returned_ctx} at this point has Each(..., In => Out =>) applied!
          #   Without configuration, this means {returned_ctx} is empty.
          # DISCUSS: this is what usually happens in Out().
          # merge all mutable parts into the original_ctx.
          wrap_ctx, _ = ITERATION_OUTPUT_PIPE.({returned_ctx: returned_ctx, aggregate: {}, original_ctx: ctx}, [])
          ctx         = wrap_ctx[:aggregate]

          # Break the loop if {block_activity} emits failure signal
          break if failing_semantic.include?(signal.to_h[:semantic]) # TODO: use generic check from older macro
        end

        return signal, [ctx, flow_options]
      end

      # This is basically Out() => {copy all mutable variables}
      ITERATION_OUTPUT_PIPE = Activity::DSL::Linear::VariableMapping::DSL.pipe_for_composable_output()
      # and this In() => {copy everything}
      ITERATION_INPUT_PIPE  = Activity::DSL::Linear::VariableMapping::DSL.pipe_for_composable_input()

      # Gets included in Debugger's Normalizer. Results in IDs like {invoke_block_activity.1}.
      def self.compute_runtime_id(ctx, captured_node:, activity:, compile_id:, **)
        # activity is the host activity
        return compile_id unless activity[:each] == true

        index = captured_node.captured_input.data[:ctx_snapshot].fetch(:index)

        ctx[:runtime_id] = "#{compile_id}.#{index}"
      end
    end

    # @api private The internals here are considered private and might change in the near future.
    def self.Each(block_activity=nil, dataset_from: nil, item_key: :item, id: Macro.id_for(block_activity, macro: :Each, hint: dataset_from), collect: false, **dsl_options_for_iterated, &block)
      dsl_options_for_iterated = block_activity if block_activity.is_a?(Hash) # Ruby 2.5 and 2.6

      block_activity, outputs_from_block_activity = Macro.block_activity_for(block_activity, &block)

      collect_options       = options_for_collect(collect: collect)
      dataset_from_options  = options_for_dataset_from(dataset_from: dataset_from)

      wrap_static_for_block_activity = task_wrap_for_iterated(
        {Activity::Railway.Out() => []}. # per default, don't let anything out.
        merge(collect_options).
        merge(dsl_options_for_iterated)
      )

      # This activity is passed into the {Runner} for each iteration of {block_activity}.
      container_activity = Activity::TaskWrap.container_activity_for(
        block_activity,
        each:         true, # mark this activity for {compute_runtime_id}.
        nodes:        [Activity::NodeAttributes.new("invoke_block_activity", nil, block_activity)], # TODO: use TaskMap::TaskAttributes
      ).merge(
        wrap_static: Hash.new(wrap_static_for_block_activity)
      )

      # DISCUSS: move to Wrap.
      termini_from_block_activity =
        outputs_from_block_activity.
          # DISCUSS: End.success needs to be the last here, so it's directly behind {Start.default}.
          sort { |a,b| a.semantic == :success ? 1 : -1 }.
          collect { |output|
            [output.signal, id: "End.#{output.semantic}", magnetic_to: output.semantic, append_to: "Start.default"]
          }

      state = Declarative::State(
        block_activity:   [block_activity, {copy: Trailblazer::Declarative::State.method(:subclass)}], # DISCUSS: move to Macro::Strategy.
        item_key:         [item_key, {}], # DISCUSS: we could even allow the wrap_handler to be patchable.
        failing_semantic: [[:failure, :fail_fast], {}],
        activity:         [container_activity, {}],
        success_signal:   [termini_from_block_activity[-1][0], {}] # FIXME: when subclassing (e.g. patching) this must be recomputed.
      )

      # {block_activity} looped. In the Stack, this will look as if {block_activity} is
      # a child of {iterate_activity}, that's why we add {block_activity} as a Node in
      # {iterate_activity}'s schema.
      iterate_strategy = Class.new(Each) do
        extend Macro::Strategy::State # now, the Wrap subclass can inherit its state and copy the {block_activity}.
        initialize!(state)
      end

      each_activity = Activity::FastTrack(termini: termini_from_block_activity) # DISCUSS: what base class should we be using?
      each_activity.extend Each::Transitive

      # {Subprocess} with {strict: true} will automatically wire all {block_activity}'s termini to the corresponding termini
      # of {each_activity} as they have the same semantics (both termini sets are identical).
      each_activity.step Activity::Railway.Subprocess(iterate_strategy, strict: true),
        id: "Each.iterate.#{block ? :block : block_activity}" # FIXME: test :id.

      Activity::Railway.Subprocess(each_activity).
        merge(id: id).
        merge(dataset_from_options) # FIXME: provide that service via Subprocess.
    end

    def self.task_wrap_for_iterated(dsl_options)
      # TODO: maybe the DSL API could be more "open" here? I bet it is, but I'm too lazy.
      activity = Class.new(Activity::Railway) do
        step({task: "iterated"}.merge(dsl_options))
      end

      activity.to_h[:config][:wrap_static]["iterated"]
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
  end

  if const_defined?(:Developer) # FIXME: how do you properly check for a gem?
    Developer::Trace::Debugger.add_normalizer_step!(
      Macro::Each.method(:compute_runtime_id),
      id:     "Each.runtime_id",
      append: :runtime_id, # so that the following {#runtime_path} picks up those changes made here.
    )
  end
end
