$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
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
