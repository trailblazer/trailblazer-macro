require "minitest/autorun"

require "trailblazer/macro"
require "trailblazer/developer"
require "trailblazer/core"
require "trailblazer/operation"

# FIXME: who loads the macros where?
[Trailblazer::Operation].each do |topology|
  _, _, builder, helper_forwarder = Trailblazer::Activity::DSL::Topology.build(
    builder: topology.config.builder,
    default_options: {},
    **Trailblazer::Macro::TOPOLOGY_BUILD_OPTIONS # :helpers and :adds
  )

  topology.config.builder = builder
  topology.extend helper_forwarder
end

T = Trailblazer::Core

Memo = Struct.new(:id, :body) do
  def self.find(id)
    return new(id, "Yo!") if id
    nil
  end
end

module Rehash
  def rehash(ctx, seq:, rehash_raise: false, **)
    seq << :rehash
    raise rehash_raise if rehash_raise
    true
  end
end

CU = Trailblazer::Core::Utils

Minitest::Spec.class_eval do
  include Trailblazer::Core::Utils::AssertRun
  include Trailblazer::Core::Utils::AssertEqual

  def trace(activity, ctx)
    ctx, flow_options, signal = Trailblazer::Activity::Railway.__(activity, ctx, **Trailblazer::Developer::Trace.options_for_canonical_invoke)

    stack = flow_options[:stack]

    output = Trailblazer::Developer::Trace::Present.(stack) do |trace_nodes:, **|
      {node_options: {trace_nodes[0] => {label: "TOP"}}}
    end.gsub(/:\d+/, "")

    return output, signal, ctx
  end

  def assert_equal(asserted, expected, *args)
    super(expected, asserted, *args)
  end
end
