module Trailblazer::Macro
  module Policy
    # Step: This generically `call`s a policy and then pushes its result to `options`.
    # You can use any callable object as a policy with this step.
    class Eval
      def initialize(name: nil, path: nil)
        @name = name
        @path = path
      end

      # incoming low-level {circuit interface}.
      # outgoing Task::Binary API.
      #
      # Retrieve the injectable {condition}, execute it and interpret its {Result} object.
      def call((ctx, flow_options), **circuit_options)
        condition = ctx[@path] # this allows dependency injection.
        result    = condition.([ctx, flow_options], **circuit_options)

        ctx[:"policy.#{@name}"]        = result[:policy] # assign the policy as a ctx variable.
        ctx[:"result.policy.#{@name}"] = result

        # flow control
        signal = result.success? ? Trailblazer::Activity::Right : Trailblazer::Activity::Left

        return signal, [ctx, flow_options]
      end
    end

    # Adds the `yield` result to the Railway and treats it like a
    # policy-compatible  object at runtime.
    def self.step(condition, name: nil, &block)
      path = :"policy.#{name}.eval"
      task = Eval.new(name: name, path: path)

      injections = {
        Trailblazer::Activity::Railway.Inject() => {
          # :"policy.default.eval"
          path => ->(*) { condition }
        }
      }

      {task: task, id: path, **injections}
    end
  end
end
