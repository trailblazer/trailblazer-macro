module Trailblazer
  module Macro
    class Each < Trailblazer::Activity::FastTrack
      # FIXME: for Strategy that wants to pass-through the exec_context, so it
      # looks "invisible" for steps.
      module Transitive
        def call(args, exec_context:, **circuit_options)
          # exec_context is our hosting Song::Activity::Cover

          to_h[:activity].call(args, exec_context: exec_context, **circuit_options)
        end

      end
      extend Transitive

      class Circuit
        def initialize(block_activity:, inner_key:, success_terminus:, failure_terminus:)
          @inner_key      = inner_key
          @block_activity = block_activity

          @success_terminus = success_terminus
          @failure_terminus = failure_terminus
        end

        def call((ctx, flow_options), runner: Run, **circuit_options) # DISCUSS: do we need {start_task}?
          dataset = ctx.fetch(:dataset)

          collected_values = dataset.collect.with_index do |element, index|
            # This new {inner_ctx} will be disposed of after invoking the item activity.
            inner_ctx = ctx.merge(
              @inner_key => element, # defaults to {:item}
              :index     => index,
              # "#{key}_index" => index,
            )

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


            #   # Break the loop if {block} emits failure signal
            #   return [signal, [ctx, flow_options]] if [:failure, :fail_fast].include?(signal.to_h[:semantic]) # TODO: use generic check from older macro
            # end
            returned_ctx[:value] # {:value} is guaranteed to be returned.
          end

          ctx[:collected_from_each] = collected_values

          return @success_terminus, [ctx, flow_options]
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
    def self.Each(block_activity=nil, dataset_from: nil, inner_key: :item, id: "Each/#{SecureRandom.hex(4)}", &block)

      # TODO: logic here sucks.
      block_activity ||= Class.new(Activity::FastTrack, &block) # TODO: use Wrap() logic!
        # include

        if dataset_from
          block_activity.extend Each::Transitive

        end




      # returns {:collected_from_each}
      success_terminus = Trailblazer::Activity::End.new(semantic: :success)
      failure_terminus = Trailblazer::Activity::End.new(semantic: :failure)

      circuit = Trailblazer::Macro::Each::Circuit.new(
        block_activity: block_activity,
        inner_key:      inner_key,

        success_terminus: success_terminus,
        failure_terminus: failure_terminus,
      )

      outputs = [ # TODO: do we want more signals out of the iteration?
        Trailblazer::Activity::Output(success_terminus, :success),
        Trailblazer::Activity::Output(failure_terminus, :failure)
      ]

      schema = Trailblazer::Activity::Schema.new(circuit,
        outputs, # outputs
        # nodes
        [Trailblazer::Activity::NodeAttributes.new("invoke_block_activity", nil, block_activity)], # TODO: use TaskMap::TaskAttributes
        # config
        Trailblazer::Activity::TaskWrap.container_activity_for(
          block_activity,
          each:         true, # mark this activity for {compute_runtime_id}.
        )
      )

      # The {Each.iterate.block} activity hosting a special {Circuit} that runs
      # {block_activity} looped. In the Stack, this will look as if {block_activity} is
      # a child of {iterate_activity}, that's why we add {block_activity} as a Node in
      # {iterate_activity}'s schema.
      iterate_activity = Trailblazer::Activity.new(schema)



      each_activity = Class.new(Macro::Each) # DISCUSS: what base class should we be using?
        if dataset_from
          dataset_task = Macro.task_adapter_for_decider(dataset_from, variable_name: :dataset)

          each_activity.step task: dataset_task, id: "dataset_from" # returns {:value}
        end

      each_activity.step Activity::Railway.Subprocess(iterate_activity),
        id: "Each.iterate.#{block ? :block : block_activity}" # FIXME: test :id.



      Activity::Railway.Subprocess(each_activity).merge(
        id: id,
        Activity::Railway.Out() => [:collected_from_each], # TODO: allow renaming without leaking {:collected_from_each} as well.
        )
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
