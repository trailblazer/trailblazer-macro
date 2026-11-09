module Trailblazer
  module Macro
    module DSL
      class Atom < Struct.new(:options)
      end

      module Normalizer
        def self.evaluate_macro(ctx, flow_options, _, first_arg:, **options)
          macro_options = first_arg
          macro_options = first_arg.(**options) if first_arg.is_a?(Atom)

          return ctx.merge(first_arg: macro_options), flow_options
        end
      end
    end
  end
end
