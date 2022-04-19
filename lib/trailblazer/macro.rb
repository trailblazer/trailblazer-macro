require "forwardable"
require "trailblazer/activity/dsl/linear"
require "trailblazer/operation" # TODO: remove this dependency

require "trailblazer/macro/model"
require "trailblazer/macro/policy"
require "trailblazer/macro/guard"
require "trailblazer/macro/pundit"
require "trailblazer/macro/nested"
require "trailblazer/macro/rescue"
require "trailblazer/macro/wrap"

module Trailblazer
  module Macro
  end

  # All macros sit in the {Trailblazer::Macro} namespace, where we forward calls from
  # operations and activities to.

  module Activity::DSL::Linear::Helper
    Constants::Policy = Trailblazer::Macro::Policy

    # Extending the {Linear::Helper} namespace is the canonical way to import
    # macros into Railway, FastTrack, Operation, etc.
    extend Forwardable
    def_delegators Trailblazer::Macro, :Model, :Nested, :Wrap, :Rescue
  end # Helper
end
