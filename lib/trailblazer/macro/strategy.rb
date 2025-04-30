module Trailblazer
  module Macro
    # {Macro::Strategy} always keeps a {block_activity} and has to define a `#call` method per macro type.
    class Strategy # We want to look like a real {Linear::Strategy}.
      class << self
        extend Forwardable
        def_delegators :block_activity, :step, :pass, :fail, :left, :Subprocess # TODO: add all DSL::Helper
      end

      # This makes {Wrap} look like {block_activity}.
      def self.to_h
        block_activity.to_h
      end

      def self.block_activity
        @state.get(:block_activity)
      end

      # DISCUSS: move this to Linear::Strategy.
      module State
        def initialize!(state)
          @state = state
        end

        def inherited(inheritor)
          super
          inheritor.initialize!(@state.copy)
        end
      end
    end
  end
end
