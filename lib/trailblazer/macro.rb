require "trailblazer/activity"
require "trailblazer/activity/dsl/linear" # TODO: remove this dependency
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
    # All macros sit in the {Trailblazer::Macro} namespace, where we forward calls from
    # operations and activities to.
    def self.forward_macros(target)
      target.singleton_class.def_delegators Trailblazer::Macro, :Model, :Wrap, :Rescue, :Nested
      target.const_set(:Policy, Trailblazer::Macro::Policy)
    end
  end
end

# TODO: Forwardable.def_delegators(Operation, Macro, :Model, :Wrap) would be amazing. It really sucks to extend a foreign class.
# Trailblazer::Operation.singleton_class.extend Forwardable
# Trailblazer::Macro.forward_macros(Trailblazer::Operation)

Trailblazer::Activity::FastTrack.singleton_class.extend Forwardable
Trailblazer::Macro.forward_macros(Trailblazer::Activity::FastTrack) # monkey-patching sucks.
