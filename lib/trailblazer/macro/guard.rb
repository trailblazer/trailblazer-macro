module Trailblazer::Macro
  module Policy
    def self.Guard(proc, name: :default, &block)
      Policy.step(Guard.build(proc), name: name)
    end

    module Guard
      def self.build(callable)
        option = Trailblazer::Option(callable)

        ->((ctx, *), **circuit_args) do
          Policy::Result.new(result: !!option.call(ctx, keyword_arguments: ctx.to_hash, **circuit_args))
        end
      end
    end
  end
end
