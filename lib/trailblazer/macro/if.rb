require 'securerandom'

module Trailblazer
  module Macro
    # Condition can be anything to be fetched from context.
    # String, Symbol or Hash preferred.
    # Example:
    #   String => 'string' -> ctx['string']
    #   Symbol => :symbol -> ctx[:symbol]
    #   Hash => {params: :condition} -> ctx[:params][:condition]
    def self.If(condition = { params: :condition }, &block)
      keys_to_dig = If::UNDIGGABLE_KEY_TYPES.include?(condition.class) ? [condition] : If.keys(condition)

      if_block = lambda do |(ctx, flow_options), **, &nested_activities|
        return [Trailblazer::Activity::Right, [ctx, flow_options]] unless If.condition(ctx, keys_to_dig)

        nested_activities.call
      end

      Wrap(if_block, id: "If(#{SecureRandom.hex(4)})", &block)
    end

    module If
      UNDIGGABLE_KEY_TYPES = [String, Symbol, Integer].freeze

      def self.keys(condition)
        result = []
        condition.each do |k, v|
          result << k
          if UNDIGGABLE_KEY_TYPES.include?(v.class)
            result << v
          else
            result.concat keys(v)
          end
        end
        result
      end

      def self.condition(context, keys_to_dig)
        return context[keys_to_dig.first] if keys_to_dig.size == 1

        keys_to_dig.reduce(context) { |digged, k| digged.try(:[], k) }
      end
    end
  end
end
