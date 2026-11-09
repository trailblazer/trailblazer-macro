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
        class Atom < DSL::Atom
          def call(*, default_options:, exec_context: default_options.fetch(:exec_context), **) # called via Normalizer.evaluate_macro
            guard = Trailblazer::Activity::Step.build(options[:provider], binary: true, exec_context: exec_context)

            return Macro::Policy.options_for_step(node: guard, name: options[:name])
          end

        end
      end
    end
  end
end
