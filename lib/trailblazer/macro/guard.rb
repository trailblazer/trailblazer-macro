module Trailblazer::Macro
  module Policy
    def self.Guard(proc, name: :default, &block)
      Policy.step(Guard.build(proc), name: name)
    end

    module Guard
      def self.build(callable)
        option = Trailblazer::Activity::Circuit::Step(callable) # DISCUSS: should we use Option here directly?

        ->(ctx, flow_options, circuit_options) do
          _, _, result = option.call(ctx, flow_options, circuit_options)

          Trailblazer::Operation::Result.new(!!result, {})
        end
      end
    end
  end
end
