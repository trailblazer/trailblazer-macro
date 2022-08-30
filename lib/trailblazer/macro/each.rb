require 'securerandom'

module Trailblazer
  module Macro
    class Each
      def initialize(dataset_getter:, inner_key:, block:)
        @dataset_getter = dataset_getter # TODO: Option here
        @inner_key      = inner_key
        @block_activity = Class.new(Activity::FastTrack, &block) # TODO: use Wrap() logic!
        outputs         = @block_activity.to_h[:outputs]
        @to_h           = {outputs: outputs}
        wrap_static    = Activity::TaskWrap.initial_wrap_static

        # DISCUSS: do we want to support In/Out for Each items?
        static_ext = Activity::DSL::Linear.VariableMapping(
          out_filters: [
            [Activity::Railway.Out(), [:value]] # we need to make sure that {:value} is returned.
          ]
        )[0]

        @wrap_static = static_ext.instance_variable_get(:@extension).(wrap_static)
      end

      attr_reader :to_h

      def call((ctx, flow_options), **circuit_options)
        elements = @dataset_getter.(ctx, keyword_arguments: ctx, **circuit_options) # Trailblazer::Option call

        raise EnumerableNotGiven unless elements.kind_of?(Enumerable) # FIXME: do we want this check?

        collected_values = []

        elements.each.with_index do |element, index|
          # This new {inner_ctx} will be disposed of after invoking the item activity.
          inner_ctx = ctx.merge(
            @inner_key => element, # defaults to {:item}
            :index     => index,
            # "#{key}_index" => index,
          )

          # signal, (returned_ctx, flow_options) = @block_activity.(
          signal, (returned_ctx, flow_options) = Activity::TaskWrap.invoke(
            @block_activity,
            [inner_ctx, flow_options],


            **circuit_options, # {circuit_options} contains {TaskWrap::Runner}.
          wrap_static: @wrap_static
          )

          collected_values << returned_ctx[:value] # {:value} is guaranteed to be returned.

          # Break the loop if {block} emits failure signal
          return [signal, [ctx, flow_options]] if [:failure, :fail_fast].include?(signal.to_h[:semantic]) # TODO: use generic check from older macro
        end

        ctx[:collected_from_each] = collected_values

        return [@to_h[:outputs].find { |output| output[:semantic] == :success }[:signal], [ctx, flow_options]] # TODO: use Wrap logic somewhow here.
      end

      def self.default_dataset(ctx, dataset:, **)
        dataset
      end

      EnumerableNotGiven = Class.new(RuntimeError)
    end

    def self.Each(enumerable=Each.method(:default_dataset), key: :item, id: "Each/#{SecureRandom.hex(4)}", &block)
      # Wrap(
        _each = Each.new(
          dataset_getter: Trailblazer::Option(enumerable),
          inner_key: key,
          block: block
        )

        Activity::Railway.Subprocess(_each).merge(id: id)

      # )
    end
  end
end
