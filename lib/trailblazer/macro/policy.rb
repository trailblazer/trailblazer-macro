module Trailblazer
  module Macro
    module Policy
      def self.build_node(*rows, policy_context:)
        rows = [
          *rows,
          [:expose_policy, :expose_policy, Circuit::Task::Adapter::LibInterface::InstanceMethod],
          [:build_result, :build_result, Circuit::Task::Adapter::LibInterface::InstanceMethod,
            connections: {true => [nil, Activity::Right], false => [nil, Activity::Left]}
          ]
        ]

        # DISCUSS: injections?
        #   injections = {                          # :"policy.default.eval"
        #     Trailblazer::Activity::Railway.Inject(path) => ->(*) { condition }
        #   }
        node = Circuit.Builder(
          *rows,
          exec_context: policy_context
        )
      end

      module Context # DISCUSS: there are other ways to share this behavior with Pundit and Guard.
        def expose_policy(lib_ctx, flow_options, (decision, policy), target_ctx:, ctx_name_for_policy: :"policy.#{name}", **) # DISCUSS: do we want the defaulting here, or Inject()?
          target_ctx[ctx_name_for_policy] = policy

          return lib_ctx.merge(target_ctx: target_ctx), flow_options, [decision, policy]
        end

        def build_result(lib_ctx, flow_options, (decision, policy), target_ctx:, **)
          target_ctx[:"result.policy.#{name}"] = Operation::Result.new(decision, {policy: policy}, nil)

          return lib_ctx.merge(target_ctx: target_ctx), flow_options, decision
        end
      end
    end # Policy
  end
end
