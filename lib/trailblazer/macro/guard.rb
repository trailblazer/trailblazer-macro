module Trailblazer
  module Macro
    module Policy
      module Constants
        module Policy
          def self.Guard(proc, name: :default, &block)
            Guard::Atom.new({name: name, provider: proc})
          end
        end
      end

      module Guard
        class Context < Struct.new(:name)
          include Macro::Policy::Context # TODO: make that unnecessary.

          def evaluate(lib_ctx, flow_options, decision, **)
            return lib_ctx, flow_options, [!!decision, "this should be a reference to the guard"]
          end
        end

        class Atom < DSL::Atom
          # Build the policy node via the normalizer.
          def build_node(exec_context:, name:, provider:, **) # called via Normalizer.evaluate_macro
            guard = Trailblazer::Activity::Step.build(provider, binary: false, exec_context: exec_context)

            policy_context = Context.new(name)

            node_for_policy = Macro::Policy.build_node(
              [:invoke_guard, node: guard],
              [:evaluate, :evaluate, Circuit::Task::Adapter::LibInterface::InstanceMethod],
              policy_context: policy_context,
            )

            {
              id: "policy.guard.#{name}",
              node_for_call_task: node_for_policy,
            }
          end

        end
      end
    end
  end
end
