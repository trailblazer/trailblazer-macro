module Trailblazer
  module Macro
    class Each < Trailblazer::Activity::FastTrack
      class Circuit
        def initialize(block_activity:, inner_key:, success_terminus:, failure_terminus:)
          @inner_key      = inner_key
          @block_activity = block_activity

          @success_terminus = success_terminus
          @failure_terminus = failure_terminus
        end

        def call((ctx, flow_options), runner: Run, **circuit_options) # DISCUSS: do we need {start_task}?
          dataset = ctx.fetch(:dataset)

          collected_values = []

          dataset.each.with_index do |element, index|
            # This new {inner_ctx} will be disposed of after invoking the item activity.
            inner_ctx = ctx.merge(
              @inner_key => element, # defaults to {:item}
              :index     => index,
              # "#{key}_index" => index,
            )

            # using this runner will make it look as if block_activity is being run consequetively within Each as if they were steps
            # Use TaskWrap::Runner to run the each block. This doesn't create the container_activity
            # and literally simply invokes {block_activity.call}, which will set its own {wrap_static}.
            signal, (returned_ctx, flow_options) = runner.(
              @block_activity,
              [inner_ctx, flow_options],
              runner: runner,
              **circuit_options,
              # wrap_static: @wrap_static,
            )

            collected_values << returned_ctx[:value] # {:value} is guaranteed to be returned.

            #   # Break the loop if {block} emits failure signal
            #   return [signal, [ctx, flow_options]] if [:failure, :fail_fast].include?(signal.to_h[:semantic]) # TODO: use generic check from older macro
            # end
          end

          ctx[:collected_from_each] = collected_values

          return @success_terminus, [ctx, flow_options]
        end

        def to_h
          {map: {@block_activity =>{}}} # FIXME.
        end
      end # Circuit

      def self.default_dataset(ctx, dataset:, **)
        dataset
      end
    end

    def self.Each(block_activity: nil, enumerable: Each.method(:default_dataset), inner_key: :item, id: "Each/#{SecureRandom.hex(4)}", &block)

      dataset_getter = enumerable

      # TODO: logic here sucks.
      block_activity ||= Class.new(Activity::FastTrack, &block) # TODO: use Wrap() logic!

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
        [Trailblazer::Activity::NodeAttributes.new("invoke_block_activity", ["# FIXME"], block_activity)],
        # config
        {wrap_static: {block_activity => Trailblazer::Activity::TaskWrap.initial_wrap_static}}
      )


      iterate_activity = Trailblazer::Activity.new(schema)



      each_activity = Class.new(Macro::Each) # DISCUSS: do we need this class? and what base class should we be using?
      each_activity.step dataset_getter, id: "dataset_getter" # returns {:value}

      each_activity.step Activity::Railway.Subprocess(iterate_activity),
        id: "Each.iterate.#{block ? :block : block_activity}" # FIXME: test :id.



      Activity::Railway.Subprocess(each_activity).merge(id: id)
    end
  end
end
