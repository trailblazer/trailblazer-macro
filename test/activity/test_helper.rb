require "minitest/autorun"

require "trailblazer/macro"
# require "trailblazer/developer"
require "trailblazer/core"

# The point of this suite is to prove we're independent of Operation's setup.
raise if Trailblazer.const_defined?(:Operation)

T = Trailblazer::Core

Minitest::Spec.class_eval do
  include Trailblazer::Core::Utils::AssertRun
  include Trailblazer::Core::Utils::AssertEqual
end

# for Railway, load the macro helpers.
[Trailblazer::Activity::Railway,].each do |topology|
  _, _, builder, helpers_module = Trailblazer::Activity::DSL::Topology.build(
    builder: topology.config.builder,
    default_options: {},
    **Trailblazer::Macro::TOPOLOGY_BUILD_OPTIONS # :helpers and :adds
  )

  topology.config.builder = builder
  topology.include helpers_module
end

# for Railway, load variable mapping like In() and Out().
[Trailblazer::Activity::Railway,].each do |topology|
  _, _, builder, helpers_module = Trailblazer::Activity::DSL::Topology.build(
    builder: topology.config.builder,
    default_options: {},
    **Trailblazer::Activity::VariableMapping::TOPOLOGY_BUILD_OPTIONS # :helpers and :adds
  )

  topology.config.builder = builder
  topology.include helpers_module
end
