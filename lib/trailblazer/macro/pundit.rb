module Trailblazer
  module Macro
    module Policy
      module Constants
        module Policy
          def self.Pundit(policy_class, action, name: :default)
            node_for_policy = Pundit.build(policy_class, action, name)

            # Macro::Policy.options_for_step(node: node_for_decision, name: name)
            # FIXME
            {
              id: path = :"policy.#{name}.eval",
              node_for_call_task: node_for_policy,
            }
          end
        end
      end

      module Pundit
        def self.build(*args, &block)
          policy_context = Context.new(*args) # just like in VariableMapping, keep logic and configuration.

          circuit = Circuit::Builder.Pipeline(
            [:build_policy, :build_policy, Circuit::Task::Adapter::StepInterface::InstanceMethod], # this is basically a Step.build(, binary: false).
            [:evaluate, :evaluate, Circuit::Task::Adapter::LibInterface::InstanceMethod#,
            #  connections: Activity::Step::Resolver::ValueOnSignal::Conditional.new([true], )
            ],
            [:build_result, :build_result, Circuit::Task::Adapter::LibInterface::InstanceMethod,
              connections: {true => [nil, Activity::Right], false => [nil, Activity::Left]}
            ],
          )

          Circuit::Node::MergeToCircuitOptions[circuit, Circuit::Processor, merge_to_circuit_options: {exec_context: policy_context}]
        end

        # Pundit::Decision is invoked at runtime when iterating the pipe.
        class Context < Struct.new(:policy_class, :action, :name)
          # Instantiate the actual policy object, and call it.
          def build_policy(ctx, current_user: nil, model: nil, **)
            _value = policy_class.new(current_user, model) # this translates to Pundit interface.
          end

          def evaluate(lib_ctx, flow_options, policy, **)
            decision = !! policy.send(action)

            return lib_ctx, flow_options, [decision, policy]
          end

          def build_result(lib_ctx, flow_options, (decision, policy), target_ctx:, **)
            target_ctx[:"result.policy.#{name}"] = Operation::Result.new(decision, {policy: policy}, nil)

            return lib_ctx.merge(target_ctx: target_ctx), flow_options, decision
          end
        end
      end
    end
  end
end
