module Trailblazer
  module Macro
    module DSL
      # You need to implement Atom#build_node.
      class Atom < Struct.new(:options)
        def call(*, default_options:, exec_context: default_options.fetch(:exec_context), **) #
          build_node(exec_context: exec_context, **options) # FIXME: test merging order here.
        end
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
