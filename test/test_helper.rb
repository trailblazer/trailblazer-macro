$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require "trailblazer/macro"

require "delegate" # Ruby 2.2
require "minitest/autorun"

require "trailblazer/developer"

module Mock
  class Result
    def initialize(bool); @bool = bool end
    def success?; @bool end
    def errors; ["hihi"] end
  end
end

module Test
  module ReturnCall
    def self.included(includer)
      includer._insert :_insert, ReturnResult, {replace: Trailblazer::Operation::Result::Build}, ReturnResult, ""
    end
  end
  ReturnResult = ->(last, input, options) { input }
end

require "pp"

# Minitest::Spec::Operation = Trailblazer::Operation

Memo = Struct.new(:id, :body) do
  def self.find(id)
    return new(id, "Yo!") if id
    nil
  end
end

require "trailblazer/activity/testing"
T = Trailblazer::Activity::Testing

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



# signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create,
#       params:               {title: "Olympia"}, # some random variable.
#       "model.class":        Hit,
#       "model.action":       :find_by,
#       "model.find_by_key":  :title, seq: []
#     )

# #:update-ok
#     signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: 1}, seq: [])
#     ctx[:model] #=> #<Song id=1, ...>
#     puts signal #=> #<Trailblazer::Activity::End semantic=:success>
# #:update-ok end


# require "trailblazer/core"
# Trailblazer::Core.convert_operation_test("test/docs/model_test.rb")
# Trailblazer::Core.convert_operation_test("test/docs/each_test.rb")
