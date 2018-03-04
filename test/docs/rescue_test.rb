require "test_helper"

class NestedRescueTest < Minitest::Spec
  #---
  # nested raise (i hope people won't use this but it works)
  A = Class.new(RuntimeError)
  Y = Class.new(RuntimeError)

  class NestedInsanity < Trailblazer::Operation
    step Rescue {
      step ->(options, **) { options["a"] = true }
      step Rescue {
        step ->(options, **) { options["y"] = true }
        success ->(options, **) { raise Y if options["raise-y"] }
        step ->(options, **) { options["z"] = true }
      }
      step ->(options, **) { options["b"] = true }
      success ->(options, **) { raise A if options["raise-a"] }
      step ->(options, **) { options["c"] = true }
      failure ->(options, **) { options["inner-err"] = true }
    }
    step ->(options, **) { options["e"] = true }, name: "nested/e"
    failure ->(options, **) { options["outer-err"] = true }, name: "nested/failure"
  end

  it { Trailblazer::Operation::Inspect.(NestedInsanity).must_match /\[>Rescue\(\d+\),>nested/ } # FIXME: better introspect tests for all id-generating macros.
  it { NestedInsanity.().inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err").must_equal %{<Result:true [true, true, true, true, true, true, nil, nil] >} }
  it { NestedInsanity.( "raise-y" => true).inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err").must_equal %{<Result:false [true, true, nil, nil, nil, nil, true, true] >} }
  it { NestedInsanity.( "raise-a" => true).inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err").must_equal %{<Result:false [true, true, true, true, nil, nil, nil, true] >} }

  #-
  # inheritance
  class UbernestedInsanity < NestedInsanity
  end

  it { UbernestedInsanity.().inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err").must_equal %{<Result:true [true, true, true, true, true, true, nil, nil] >} }
  it { UbernestedInsanity.( "raise-a" => true).inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err").must_equal %{<Result:false [true, true, true, true, nil, nil, nil, true] >} }
end

class RescueTest < Minitest::Spec

=begin
plain Rescue()
=end
  class RescueWithoutHandlerTest < Minitest::Spec
    Memo = Class.new

    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Rescue() {
        step :update
        step :rehash
      }
      step :notify
      fail :log_error
      #~methods
      include Test::Methods
      #~methods end
    end

    it { Memo::Create.( { seq: [] } ).inspect(:seq, :exception_class).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify], nil] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >} }
  end

=begin
Rescue( handler: X )
=end
  class RescueWithHandlerTest < Minitest::Spec
    Memo = Class.new

    class MyHandler
      def self.call(exception, (ctx), *)
        ctx[:exception_class] = exception.class
      end
    end

    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Rescue( RuntimeError, handler: MyHandler ) {
        step :update
        step :rehash
      }
      step :notify
      fail :log_error
      #~methods
      include Test::Methods
      #~methods end
    end

    it { Memo::Create.( { seq: [], } ).inspect(:seq, :exception_class).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify], nil] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq, :exception_class).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error], RuntimeError] >} }
  end


end
