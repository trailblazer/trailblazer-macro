$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require "minitest/autorun"

require "trailblazer/developer"
require "trailblazer/operation"
require "trailblazer/activity/testing"
require "trailblazer/macro"

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
    raise "nope!" if rehash_raise
    true
  end
end

Minitest::Spec.include Trailblazer::Activity::Testing::Assertions

Minitest::Spec.class_eval do
  def trace(activity, ctx)
    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(activity, [ctx, {}])
    return Trailblazer::Developer::Trace::Present.(stack, node_options: {stack.to_a[0]=>{label: "TOP"}}).gsub(/:\d+/, ""), signal, ctx
  end
end
