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
def convert_operation_test(filepath)
  within_marker = false
  op_test =
  File.foreach(filepath).collect do |line|
    if line.match(/#:[\w]+/)
      within_marker = true
    end
    if line.match(/#:.+ end/)
      within_marker = false
    end

    line = line.sub("< Trailblazer::Activity::Railway", "< Trailblazer::Operation")
    line = line.gsub("::Activity", "::Operation")

    # if within_marker
      line = line.sub("signal, (ctx, _) =", "result =")
      line = line.sub("ctx[", "result[")

      if match = line.match(/(Trailblazer::Operation\.\(([\w:]+),\s?)/)
        activity = match[2]

        line = line.sub(match[0], "#{activity}.(")
      end

      if match = line.match(/(\s+)puts signal.+(:\w+)>/)
        semantic = match[2]
        line = "#{match[1]}result.success? # => #{semantic == ":success" ?  true : false}\n"
      end
    # end

    line = line.sub("assert_equal ctx", "assert_equal result")
    line = line.sub("assert_equal signal", "assert_equal result.event")

    line
  end

  File.write "test/operation/" + File.basename(filepath), op_test.join("")
end

convert_operation_test("test/docs/model_test.rb")
