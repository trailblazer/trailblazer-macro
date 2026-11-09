module Trailblazer
  module Macro
    module Policy
      def self.build_node(*rows, policy_context:)
        rows = [
          *rows,
          [:build_result, :build_result, Circuit::Task::Adapter::LibInterface::InstanceMethod,
            connections: {true => [nil, Activity::Right], false => [nil, Activity::Left]}
          ]
        ]

        circuit = Circuit::Builder.Pipeline(*rows)

        Circuit::Node::MergeToCircuitOptions[circuit, Circuit::Processor, merge_to_circuit_options: {exec_context: policy_context}]
      end

      module Context # DISCUSS: there are other ways to share this behavior with Pundit and Guard.
        def build_result(lib_ctx, flow_options, (decision, policy), target_ctx:, **)
          target_ctx[:"result.policy.#{name}"] = Operation::Result.new(decision, {policy: policy}, nil)

          return lib_ctx.merge(target_ctx: target_ctx), flow_options, decision
        end
      end

      # Adds the `yield` result to the Railway and treats it like a
      # policy-compatible  object at runtime.
      # def self.step(condition, name: nil, &block)
      #   path = :"policy.#{name}.eval"
      #   task = Eval.new(name: name, path: path)

      #   injections = {                          # :"policy.default.eval"
      #     Trailblazer::Activity::Railway.Inject(path) => ->(*) { condition }
      #   }

      #   {task: task, id: path}.merge(injections)
      # end
    end
  end
end
