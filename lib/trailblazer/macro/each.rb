require 'securerandom'

module Trailblazer
  module Macro
    def self.Each(enumerable, key:, id: "Each/#{SecureRandom.hex(4)}", &block)
      Wrap(
        Each.for(Trailblazer::Option(enumerable), key: key),
        id: id,
        &block
      )
    end

    module Each
      EnumerableNotGiven = Class.new(RuntimeError)

      def self.for(enumerable, key:)
        ->((ctx, flow_options), **circuit_options, &nested_activity) do
          elements = enumerable.(ctx, keyword_arguments: ctx, **circuit_options) # Trailblazer::Option call
          raise EnumerableNotGiven unless elements.kind_of?(Enumerable)

          elements.each.with_index do |element, index|
            ctx_with_element = ctx.merge(
              key => element,
              "#{key}_index" => index
            )

            signal, (ctx, flow_options) = nested_activity.(
              [ctx_with_element, flow_options],
              wrapped_kwargs: circuit_options
            )

            # Break the loop if {block} emits failure signal
            return [signal, [ctx, flow_options]] if [:failure, :fail_fast].include?(signal.to_h[:semantic])
          end

          return [Operation::Railway.pass!, [ctx, flow_options]]
        end
      end
    end
  end
end
