module Trailblazer
  module Macro
    def self.If(condition, name: :default, id: Macro.id_for(condition, macro: :If, hint: condition), &block)
      unless block_given?
        raise ArgumentError, "If() requires a block"
      end

      option = Trailblazer::Option(condition)
      wrap = ->((ctx, flow_options), **circuit_args, &block) {
        ctx[:"result.condition.#{name}"] = result =
          option.call(ctx, keyword_arguments: ctx.to_hash, **circuit_args)

        if result
          block.call
        else
          [Trailblazer::Activity::Right, [ctx, flow_options]]
        end
      }

      Wrap(wrap, id: id, &block)
    end
  end
end
