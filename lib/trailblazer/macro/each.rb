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
      my_lowlevel_inject_filter = ->((ctx, flow_options), index:, **circuit_options) { [index, ctx] }
      my_filter_builder = ->(*) { Trailblazer::Activity::DSL::Linear::VariableMapping::SetVariable.new(name: "bla.FIXME", filter: my_lowlevel_inject_filter, write_name: :index, user_filter: nil) }
      # filter to set ctx[item_key]
      my_lowlevel_inject_filter_item = ->((ctx, flow_options), item:, **circuit_options) { [item, ctx] }
      my_filter_builder_item = ->(*) { Trailblazer::Activity::DSL::Linear::VariableMapping::SetVariable.new(name: "bla.FIXME.item_key", filter: my_lowlevel_inject_filter_item, write_name: item_key, user_filter: nil) }

      # DISCUSS: move to Wrap.
      # TODO: if a patched step in the iterated activity would add another teminus, this would be inconsistent.
      #       we'd have to recompute this via `inherited`.
        termini_from_block_activity =
          outputs_from_block_activity.
            # DISCUSS: End.success needs to be the last here, so it's directly behind {Start.default}.
            sort { |a,b| a.semantic == :success ? 1 : -1 }.
            collect { |output|
              [output.signal, id: "End.#{output.semantic}", magnetic_to: output.semantic, append_to: "Start.default"]
            }

      each_activity = Trailblazer::Activity::Railway(termini: termini_from_block_activity) do

        # TODO: make publicly configurable.
        @state.update!(:fields) do |fields|
          fields.merge(
            failing_semantics: [:failure, :fail_fast],
            each: true, # mark this activity for {compute_runtime_id}.
          )
        end

        step Subprocess(iterated_activity, strict: true),
            id: "iterated_block",
            Inject(:index, filter_builder: my_filter_builder) => my_lowlevel_inject_filter,
            Inject(:item, filter_builder: my_filter_builder_item) => my_lowlevel_inject_filter_item,
            Out() => [], # per default, don't let anything out.
            **Each.options_for_collect(collect: collect),
            **dsl_options_for_iterated
      end

      each_activity.class_eval do
        def self.call((ctx, flow_options), runner:, **circuit_options)
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
            signal, (ctx, flow_options) = runner.(iterated_railway, [ctx, flow_options], runner: runner, **circuit_options, activity: self, **each_options_for_iterated)

            # Break the loop if {iterated_activity} emits a failure signal.
            break if failing_semantics.include?(signal.to_h[:semantic]) # TODO: use generic check from older macro
          end

          return signal, [ctx, flow_options]
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
        def call(args, exec_context:, **circuit_options)
          # exec_context is our hosting Song::Activity::Cover
          to_h[:activity].call(args, exec_context: exec_context, **circuit_options)
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
      def self.compute_runtime_id(ctx, trace_node:, activity:, compile_id:, **)
        # activity is the iterated activity
        fields = activity.to_h[:fields]
        return compile_id unless fields && fields[:each] == true

        # Developer::Trace::Snapshot::Ctx.ctx_snapshot_for(trace_node.snapshot_before, .data
# FIXME: BETTER API, we need access to stack now


        # index = trace_node.snapshot_before.data[:ctx_snapshot].fetch(:index)
        index = trace_node.snapshot_before.data[:ctx_variable_changeset].find { |name, version, value| name == :index }[2]

        ctx[:runtime_id] = "#{compile_id}.#{index}"
      end
    end

    # @api private The internals here are considered private and might change in the near future.
    def self.Each__FIXME(block_activity=nil, dataset_from: nil, item_key: :item, id: Macro.id_for(block_activity, macro: :Each, hint: dataset_from), collect: false, **dsl_options_for_iterated, &block)
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
        id:        "invoke_block_activity",
        # merged into {:config}:
          each:   true, # mark this activity for {compute_runtime_id}.
      ).merge(
        outputs: outputs_from_block_activity,
        fields: {task_wrap_extensions: Activity::DSL::Linear::Strategy::INITIAL_TASK_WRAP_EXTENSIONS} # DISCUSS: shouldn't this be part of {:config}? # FIXME: too much knowledge about internals.
      )

      # FIXME: we can't pass {wrap_static: wrap_static_for_block_activity} into {#container_activity_for}
      #        because when patching, the container_activity is not recompiled, so we need the Hash here
      #        with defaulting.
      # FIXME: this "hack" is only here to satify patching.
      config = container_activity[:config].merge(wrap_static: Hash.new(wrap_static_for_block_activity))
      container_activity.merge!(config: config)

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

      # |-- Each/composers_for_each
      # |   |-- Start.default
      # |   |-- Each.iterate.block            This is Class.new(Each), outputs_from_block_activity
      # |   |   |-- invoke_block_activity.0      step :invoke_block_activity.0
      # |   |   |   |-- Start.default
      # |   |   |   |-- notify_composers
      # |   |   |   `-- End.success
      # |   |   `-- invoke_block_activity.1      step "invoke_block_activity.1"
      # |   |       |-- Start.default
      # |   |       |-- notify_composers
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


  end

  if const_defined?(:Developer) # FIXME: how do you properly check for a gem?
    Developer::Trace::Debugger.add_normalizer_step!(
      Macro::Each.method(:compute_runtime_id),
      id:     "Each.runtime_id",
      append: :runtime_id, # so that the following {#runtime_path} picks up those changes made here.
    )
  end
end
