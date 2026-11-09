module Trailblazer
  module Macro
    module Policy
      module Constants
        module Policy
          def self.Pundit(policy_class, action, name: :default)
            node_for_policy = Pundit.build(policy_class, action, name)

            {
              id: :"policy.pundit.#{name}",
              node_for_call_task: node_for_policy,
            }
          end
        end
      end

      module Pundit
        def self.build(*args, &block)
          policy_context = Context.new(*args) # just like in VariableMapping, keep logic and configuration.

          Macro::Policy.build_node(
            [:build_policy, :build_policy, Circuit::Task::Adapter::StepInterface::InstanceMethod], # this is basically a Step.build(, binary: false).
            [:evaluate, :evaluate, Circuit::Task::Adapter::LibInterface::InstanceMethod],
            policy_context: policy_context,
          )
        end

        # Pundit::Decision is invoked at runtime when iterating the pipe.
        class Context < Struct.new(:policy_class, :action, :name)
          include Macro::Policy::Context

          # Instantiate the actual policy object, and call it.
          def build_policy(ctx, current_user: nil, model: nil, **)
            _value = policy_class.new(current_user, model) # this translates to Pundit interface.
          end

          def evaluate(lib_ctx, flow_options, policy, **)
            decision = !! policy.send(action)

            return lib_ctx, flow_options, [decision, policy]
          end
        end
      end
    end
  end
end
