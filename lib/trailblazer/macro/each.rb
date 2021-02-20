require "securerandom"

module Trailblazer
  module Macro
    def self.Each(source:, target:, id: "Each/#{SecureRandom.hex(4)}", &block)
      activity = Class.new(Trailblazer::Activity::Railway, &block)
      wrapped = Wrapper.new(activity, source, target)

      { task: wrapped, id: id }
    end

    class Wrapper
      def initialize(activity, source, target)
        @activity = activity
        @source = source
        @target = target
      end

      def call((ctx, flow_options), **circuit_options)
        if execute_iterator([ctx, flow_options], circuit_options) == :error
          signal = Trailblazer::Activity::Left
        else
          signal = Trailblazer::Activity::Right
        end

        ctx.delete(@target)

        return signal, [ctx, flow_options]
      end

      def execute_iterator((ctx, flow_options), **circuit_options)
        ctx[@source].each do |element|
          ctx.merge!({ @target => element })
          call_result = call_wrapped_activity([ctx, flow_options], circuit_options)
          break(:error) if call_result[0].to_h[:semantic] != :success
        end
      end

      def call_wrapped_activity((ctx, flow_options), **circuit_options)
        @activity.to_h[:activity].([ctx, flow_options], **circuit_options) # :exec_context is this instance.
      end
    end
  end
end
