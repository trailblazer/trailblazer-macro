module Trailblazer
  module Macro
    class Each# < Trailblazer::Activity::FastTrack
      # FIXME: for Strategy that wants to pass-through the exec_context, so it
      # looks "invisible" for steps.
      module Transitive
        def call(args, exec_context:, **circuit_options)
          # exec_context is our hosting Song::Activity::Cover

          to_h[:activity].call(args, exec_context: exec_context, **circuit_options)
        end

      end

      class Circuit
        def initialize(block_activity:, item_key:)
          @item_key      = item_key
          @block_activity = block_activity

          @failing_semantic = [:failure, :fail_fast]
        end

        def call((ctx, flow_options), runner: Run, **circuit_options) # DISCUSS: do we need {start_task}?
          dataset = ctx.fetch(:dataset)
          signal  = @success_terminus

          collected_values = []

          # I'd like to use {collect} but we can't {break} without losing the last iteration's result.
          dataset.each_with_index do |element, index|
            # This new {inner_ctx} will be disposed of after invoking the item activity.
            # DISCUSS: this is what happens when you use In().
            _inner_ctx = ctx.merge(
              @item_key => element, # defaults to {:item}
              :index     => index,
              # "#{key}_index" => index,
            )

            # TODO: test aliasing
            inner_ctx = Trailblazer.Context(_inner_ctx, {}, **circuit_options) # everything we write to inner_ctx is guaranteed to be data from iterated.

            # using this runner will make it look as if block_activity is being run consequetively within {Each.iterate} as if they were steps
            # Use TaskWrap::Runner to run the each block. This doesn't create the container_activity
            # and literally simply invokes {block_activity.call}, which will set its own {wrap_static}.
            signal, (returned_ctx, flow_options) = runner.(
              @block_activity,
              [inner_ctx, flow_options],
              runner: runner,
              **circuit_options,
              # wrap_static: @wrap_static,
            )

            #
            # {returned_ctx} at this point has Each(..., In => Out =>) applied!
            #

# TODO: decompose ctx
            # collected_values << returned_ctx[:value] # {:value} is guaranteed to be returned.

            # DISCUSS: this is what usually happens in Out().
            outer_ctx, mutable_ctx = returned_ctx.decompose
            # raise mutable_ctx.keys.inspect
            puts "@@@@@ merging #{mutable_ctx.inspect}"
            # ctx.merge(mutable_ctx) # TODO: next iteration can see that!
            mutable_ctx.each { |k,v| ctx[k] = v } # FIXME: copied from Out().


            # mutable_ctx are the parts the user wants written outside.


            # Break the loop if {block_activity} emits failure signal
            break if @failing_semantic.include?(signal.to_h[:semantic]) # TODO: use generic check from older macro
          end

          # ctx[:collected_from_each] = collected_values


          return signal, [ctx, flow_options]
        end
      end # Circuit

      # Gets included in Debugger's Normalizer. Results in IDs like {invoke_block_activity.1}.
      def self.compute_runtime_id(ctx, captured_node:, activity:, compile_id:, **)
        # activity is the host activity
        return compile_id unless activity[:each] == true

        index = captured_node.captured_input.data[:ctx_snapshot].fetch(:index)

        ctx[:runtime_id] = "#{compile_id}.#{index}"
      end
    end


    # @api private The internals here are considered private and might change in the near future.
    def self.Each(block_activity=nil, dataset_from: nil, item_key: :item, id: "Each/#{SecureRandom.hex(4)}", **dsl_options_for_iterated, &block)

      block_activity, outputs_from_block_activity = Macro.block_activity_for(block_activity, &block)

      # returns {:collected_from_each}
      circuit = Trailblazer::Macro::Each::Circuit.new(
        block_activity: block_activity,
        item_key:      item_key,
      )

      schema = Trailblazer::Activity::Schema.new(
        circuit,
      # Those outputs we simply wire through to the Each() activity.
        outputs_from_block_activity, # outputs: we reuse block_activity's outputs.
        # nodes
        [Trailblazer::Activity::NodeAttributes.new("invoke_block_activity", nil, block_activity)], # TODO: use TaskMap::TaskAttributes
        # config
        Trailblazer::Activity::TaskWrap.container_activity_for(
          block_activity,
          each:         true, # mark this activity for {compute_runtime_id}.
          wrap_static:  task_wrap_for_iterated(
            Activity::Railway.Out() => [], # per default, don't let anything out.
            **dsl_options_for_iterated
          ), # In/Out per iteration
        )
      )

      # The {Each.iterate.block} activity hosting a special {Circuit} that runs
      # {block_activity} looped. In the Stack, this will look as if {block_activity} is
      # a child of {iterate_activity}, that's why we add {block_activity} as a Node in
      # {iterate_activity}'s schema.
      iterate_activity = Trailblazer::Activity.new(schema)

      # TODO: move to Wrap.
      termini_from_block_activity =
        outputs_from_block_activity.
          # DISCUSS: End.success needs to be the last here, so it's directly behind {Start.default}.
          sort { |a,b| a.semantic ==:success ? 1 : 0 }.
          collect { |output|
            [output.signal, id: "End.#{output.semantic}", magnetic_to: output.semantic, append_to: "Start.default"]
          }

      # each_activity = Class.new(Macro::Each) # DISCUSS: what base class should we be using?
      each_activity = Activity::FastTrack(termini: termini_from_block_activity) # DISCUSS: what base class should we be using?
      each_activity.extend Each::Transitive

      # if dataset_from
      #   dataset_task = Macro.task_adapter_for_decider(dataset_from, variable_name: :dataset)

      #   each_activity.step task: dataset_task, id: "dataset_from" # returns {:dataset}
      # end

      # {Subprocess} with {strict: true} will automatically wire all {block_activity}'s termini to the corresponding termini
      # of {each_activity} as they have the same semantics (both termini sets are identical).
      each_activity.step Activity::Railway.Subprocess(iterate_activity, strict: true),
        id: "Each.iterate.#{block ? :block : block_activity}" # FIXME: test :id.

      Activity::Railway.Subprocess(each_activity).merge(
        id: id,
        # Activity::Railway.Out() => [:collected_from_each], # TODO: allow renaming without leaking {:collected_from_each} as well.

        Activity::Railway.In() => ->(ctx, **) { ctx }, # FIXME: FUCK THIS. implement {always: true}
        Activity::Railway.Inject(:dataset, always: true) => dataset_from, # {ctx[:dataset]} is private to {each_activity}.

      )
    end

    def self.task_wrap_for_iterated(**dsl_options)
      # TODO: maybe the DSL API could be more "open" here? I bet it is, but I'm too lazy.
      activity = Class.new(Activity::Railway) do
        step task: "iterated", **dsl_options
      end

      activity.to_h[:config][:wrap_static]["iterated"]
    end

    def self.task_wrap_for_iterator(**dsl_options)
      task_wrap_for_iterated(**dsl_options)
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
