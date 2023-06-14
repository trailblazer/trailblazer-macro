$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require "minitest/autorun"

require "trailblazer/macro"
require "trailblazer/developer"
require "trailblazer/activity/testing"

T = Trailblazer::Activity::Testing

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

Minitest::Spec.include Trailblazer::Activity::Testing::Assertions

Minitest::Spec.class_eval do
  def trace(activity, ctx)
    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(activity, [ctx, {}])

    output = Trailblazer::Developer::Trace::Present.(stack) do |trace_nodes:, **|
      {node_options: {trace_nodes[0] => {label: "TOP"}}}
    end.gsub(/:\d+/, "")

    return output, signal, ctx
  end
end

# Trailblazer::Core.convert_operation_test("test/docs/composable_variable_mapping_test.rb")
