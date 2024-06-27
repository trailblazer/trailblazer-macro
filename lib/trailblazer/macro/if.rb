module Trailblazer
  module Macro
    def self.If(condition, name: :default, id: Macro.id_for(condition, macro: :If, hint: condition), &block)
      unless block_given?
        raise ArgumentError, "If() requires a block"
      end

      block_activity, outputs = Macro.block_activity_for(nil, &block)
      success_output = outputs.find { |output| output.semantic == :success }
      state = Declarative::State(
        block_activity:   [block_activity, {copy: Trailblazer::Declarative::State.method(:subclass)}],
        name:             [name, {}],
        success_signal:   [success_output.signal, {}]
      )

      task = Class.new(If) do
        extend Macro::Strategy::State
        initialize!(state)
      end

      merge = [
        [Nested::Decider.new(condition), id: "If.compute_condition", prepend: "task_wrap.call_task"],
      ]

      task_wrap_extension = Activity::TaskWrap::Extension::WrapStatic.new(extension: Activity::TaskWrap::Extension(*merge))

      Activity::Railway.Subprocess(task).merge(
        id:         id,
        extensions: [task_wrap_extension],
      )
    end
  end

  class If < Macro::Strategy
    def self.call((ctx, flow_options), **circuit_options)
      name = @state.get(:name)
      ctx[:"result.condition.#{name}"] = flow_options[:decision]

      if flow_options[:decision]
        Activity::Circuit::Runner.(block_activity, [ctx, flow_options], **circuit_options)
      else
        [@state.get(:success_signal), [ctx, flow_options]]
      end
    end
  end
end
