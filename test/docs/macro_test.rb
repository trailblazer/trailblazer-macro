require "test_helper"

class DocsMacroTest < Minitest::Spec
  #:simple
  module Macro
    def self.MyPolicy(allowed_role: "admin")
      step = ->(input, options) { options["current_user"].type == allowed_role }

      {task: step, id: "my_policy.#{allowed_role}"} # :before, :replace, etc. work, too.
    end
  end
  #:simple end

  #:simple-op
  class Create < Trailblazer::Operation
    step Macro::MyPolicy( allowed_role: "manager" )
    # ..
  end
  #:simple-op end

=begin
  it do
  #:simple-pipe
    puts Create["pipetree"].inspect(style: :rows) #=>
     0 ========================>operation.new
     1 ====================>my_policy.manager
  #:simple-pipe end
  end
=end

  it { assert_equal Trailblazer::Developer.railway(Create), %{[>my_policy.manager]} }
end


class MacroAssignVariableTest < Minitest::Spec
  it do
    my_exec_context = Class.new do
      def my_dataset(ctx, my_array:, **)
        my_array.reverse
      end
    end.new

    dataset_task = Trailblazer::Macro.task_adapter_for_decider(:my_dataset, variable_name: :dataset)

    signal, (ctx, _) = dataset_task.([{my_array: [1,2]}, {}], exec_context: my_exec_context)

    assert_equal signal, Trailblazer::Activity::Right
    assert_equal ctx.inspect, %{{:my_array=>[1, 2], :dataset=>[2, 1]}}
  end
end

# injectable option
# nested pipe
# using macros in macros
