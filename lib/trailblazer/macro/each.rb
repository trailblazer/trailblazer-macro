module Trailblazer
  module Macro
    class Each < Trailblazer::Activity::FastTrack
      class Circuit
        def initialize(block_activity:, inner_key:)
          @inner_key      = inner_key
          @block_activity = block_activity
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

          return Activity::Right, [ctx, flow_options]
        end

        def to_h
          {map: {@block_activity =>{}}} # FIXME.
        end
      end # Circuit

      class Iterate < Trailblazer::Activity

      end


      def self.default_dataset(ctx, dataset:, **)
        dataset
      end

      # EnumerableNotGiven = Class.new(RuntimeError)


# problem is that {iterate} gets traced as an activity. iterate instead should be an activity with its own circuit logic that uses runtime dataset.

      # def self.iterate(ctx, dataset:, inner_key:, block_activity:, **)
#       def self.iterate((ctx, flow_options), **circuit_options)
#         puts "@@@@@? #{ctx.keys.inspect}"
#         inner_key = ctx.fetch(:inner_key) # TODO: hm... keyword args would be better.
#         dataset = ctx.fetch(:dataset)
#         block_activity = ctx.fetch(:block_activity)

# puts "@@@@@ before TW>>> #{circuit_options[:activity].inspect}"


#           # return [@to_h[:outputs].find { |output| output[:semantic] == :success }[:signal], [ctx, flow_options]] # TODO: use Wrap logic somewhow here.
#         end

#         # {:collected_from_each}
#         return Activity::Right, [ctx, flow_options]
#       end
    end

    def self.Each(block_activity=nil, enumerable: Each.method(:default_dataset), inner_key: :item, id: "Each/#{SecureRandom.hex(4)}", &block)

      dataset_getter = enumerable

      # TODO: logic here sucks.
      block_activity ||= Class.new(Activity::FastTrack, &block) # TODO: use Wrap() logic!

      # returns {:collected_from_each}
      each_activity = Class.new(Macro::Each) # DISCUSS: do we need this class? and what base class should we be using?
      each_activity.step dataset_getter, id: "dataset_getter" # returns {:value}
      each_activity.step task: Each.method(:iterate), id: "iterate",
        Activity::Railway.In() => ->(ctx, dataset:, **) {
          ctx = ctx.merge(

            inner_key:      inner_key,
            block_activity: block_activity,  # FIXME: visible in the {block_activity} ctx.
            dataset:        dataset,

          )
        }#,
        #Activity::Railway.In() => [:dataset] # from {dataset_getter}

        # TODO: Inject(always: true) => {inner_key: ->(*) { inner_key }}

      # TODO: this is only for Introspect: tracing will try to look up {block_activity} in {each_activity}.
      puts "@@@@@ each_activity #{each_activity.inspect}"
      puts "@@@@@ block_activity #{block_activity.inspect}"
      each_activity.step task: block_activity,
        magnetic_to: :dontevercallme,
        id: "Each.iterate.#{block ? :block : block_activity}" # FIXME: test :id.






      Activity::Railway.Subprocess(each_activity).merge(id: id)
    end
  end
end
