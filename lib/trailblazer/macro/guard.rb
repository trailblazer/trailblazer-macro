module Trailblazer::Macro
  module Policy
    # noinspection RubyClassMethodNamingConvention
    def self.Guard(proc, name: :default, &_block)
      Policy.step(Guard.build(proc), name: name)
    end

    module Guard
      def self.build(callable)
        option = Trailblazer::Option(callable)

        ->((ctx, *), **circuit_args) do
          Trailblazer::Operation::Result.new(!!option.call(ctx, keyword_arguments: ctx.to_hash, **circuit_args), {})
        end
      end
    end
  end
end
