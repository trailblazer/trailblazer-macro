require "test_helper"

class AtomTest < Minitest::Spec
  it "A Macro::DSL::Atom will be executed by the normalizer in the very beginning, and your options are merged over the normalizer **kwargs" do
    my_atom = Class.new(Trailblazer::Macro::DSL::Atom) do
      def build_node(**options_we_see)
        {

          node_for_call_task: ->(lib_ctx, flow_options, *) do
            lib_ctx[:target_ctx][:seq] << options_we_see
            return lib_ctx, flow_options, Trailblazer::Activity::Right
          end
        }
      end
    end

    my_activity = Class.new(Trailblazer::Operation) do
      step my_atom.new({mode: :active, bogus: true}), id: :bla, bogus: false
    end

    assert_run my_activity, seq: [{exec_context: my_activity.config.builder.default_options[:step][:exec_context], mode: :active, bogus: true}], terminus: :success
  end
end
