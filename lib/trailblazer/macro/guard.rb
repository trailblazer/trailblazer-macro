module Trailblazer::Macro
  module Policy
    def self.Guard(proc, name: :default, &block)
      Policy.step(Guard.build(proc), name: name)
    end

    module Guard
      def self.build(callable)
        option = Trailblazer::Option::KW(callable)

        # this gets wrapped in a Operation::Result object.
        ->((options, *), circuit_args) do
          Trailblazer::Operation::Result.new(!!option.call(options, circuit_args), {})
        end
      end
    end
  end
end
