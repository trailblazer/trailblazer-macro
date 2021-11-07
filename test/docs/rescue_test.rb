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
        pass ->(options, **) { raise Y if options["raise-y"] }
        step ->(options, **) { options["z"] = true }
      }
      step ->(options, **) { options["b"] = true }
      pass ->(options, **) { raise A if options["raise-a"] }
      step ->(options, **) { options["c"] = true }
      fail ->(options, **) { options["inner-err"] = true }
    }
    step ->(options, **) { options["e"] = true }, id: "nested/e"
    fail ->(options, **) { options["outer-err"] = true }, id: "nested/failure"
  end

  it { Trailblazer::Developer.railway(NestedInsanity).must_match /\[>Rescue\(.{8}\),>nested/ } # FIXME: better introspect tests for all id-generating macros.
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
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end

    it { Memo::Create.( { seq: [] } ).inspect(:seq, :exception_class).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify], nil] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >} }
  end

=begin
Rescue( handler: X )
=end
  class RescueWithClassHandlerTest < Minitest::Spec
    Memo = Class.new

    #:rescue-handler
    class MyHandler
      def self.call(exception, (ctx), *)
        ctx[:exception_class] = exception.class
      end
    end
    #:rescue-handler end

    #:rescue
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Rescue( RuntimeError, handler: MyHandler ) {
        step :update
        step :rehash
      }
      step :notify
      fail :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end
    #:rescue end

    it { Memo::Create.( { seq: [], } ).inspect(:seq, :exception_class).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify], nil] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq, :exception_class).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error], RuntimeError] >} }
  end

  class RescueWithModuleHandlerTest < Minitest::Spec
    Memo = Class.new

    module MyHandler
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
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
    end

    it { Memo::Create.( { seq: [], } ).inspect(:seq, :exception_class).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify], nil] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq, :exception_class).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error], RuntimeError] >} }
  end

=begin
Rescue( handler: :instance_method )
=end
  class RescueWithMethodHandlerTest < Minitest::Spec
    Memo = Class.new

    #:rescue-method
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Rescue( RuntimeError, handler: :my_handler ) {
        step :update
        step :rehash
      }
      step :notify
      fail :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end

      def my_handler(exception, (ctx), *)
        ctx[:exception_class] = exception.class
      end
    end
    #:rescue-method end

    it { Memo::Create.( { seq: [], } ).inspect(:seq, :exception_class).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify], nil] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq, :exception_class).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error], RuntimeError] >} }
  end

=begin
Rescue(), fast_track: true {}
=end
  class RescueWithFastTrack < Minitest::Spec
    Memo = Class.new

    #:rescue-fasttrack
    class Memo::Create < Trailblazer::Operation
      rescue_block = ->(*) {
        step :update, Output(:failure) => End(:fail_fast)
        step :rehash
      }

      step :find_model
      step Rescue(&rescue_block), fail_fast: true
      step :notify
      fail :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error, :rehash)
    end

    it { Memo::Create.( { seq: [], } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    it { Memo::Create.( { seq: [], update: false } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update]] >} }
  end
end
