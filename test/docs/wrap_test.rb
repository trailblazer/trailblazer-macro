require "test_helper"

class DocsWrapTest < Minitest::Spec
=begin
When success: return the block's returns
When raise:   return {Railway.fail!}
=end
  #:wrap-handler
  class HandleUnsafeProcess
    def self.call((ctx, flow_options), *, &block)
      yield # calls the wrapped steps
    rescue
      ctx[:exception] = $!.message
      [ Trailblazer::Operation::Railway.fail!, [ctx, flow_options] ]
    end
  end
  #:wrap-handler end

  #:wrap
  class Memo::Create < Trailblazer::Operation
    step :find_model
    step Wrap( HandleUnsafeProcess ) {
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
  #:wrap end

  it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
  it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >} }

=begin
Tracing with Wrap()
=end
  it do
    options = { seq: [] }
    #:trace-call
    result  = Memo::Create.trace( options )
    #:trace-call end
    result.wtf.gsub("\n", "").must_match /.*Start.*find_model.*Wrap.*update.*rehash.*success.*notify.*success/
=begin
#:trace-success
result.wtf? #=>
|-- #<Trailblazer::Activity::Start semantic=:default>
|-- find_model
|-- Wrap/85
|   |-- #<Trailblazer::Activity::Start semantic=:default>
|   |-- update
|   |-- rehash
|   `-- #<Trailblazer::Operation::Railway::End::Success semantic=:success>
|-- notify
`-- #<Trailblazer::Operation::Railway::End::Success semantic=:success>
#:trace-success end
=end
  end

=begin
Writing into ctx in a Wrap()
=end
  it { Memo::Create.( { seq: [], rehash_raise: true } )[:exception].must_equal("nope!") }

=begin
When success: return the block's returns
When raise:   return {Railway.fail!}, but wire Wrap() to {fail_fast: true}
=end
  class WrapGoesIntoFailFastTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          yield # calls the wrapped steps
        rescue
          [ Trailblazer::Operation::Railway.fail!, [ctx, {}] ]
        end
      end

      step :find_model
      step Wrap( HandleUnsafeProcess ) {
        step :update
        step :rehash
      }, fail_fast: true
      step :notify
      fail :log_error

      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end

    it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash]] >} }
  end

=begin
When success: return the block's returns
When raise:   return {Railway.fail_fast!} and configure Wrap() to {fast_track: true}
=end
  class WrapGoesIntoFailFastViaFastTrackTest < Minitest::Spec
    Memo = Module.new

    #:fail-fast-handler
    class HandleUnsafeProcess
      def self.call((ctx), *, &block)
        yield # calls the wrapped steps
      rescue
        [ Trailblazer::Operation::Railway.fail_fast!, [ctx, {}] ]
      end
    end
    #:fail-fast-handler end

    #:fail-fast
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Wrap( HandleUnsafeProcess ) {
        step :update
        step :rehash
      }, fast_track: true
      step :notify
      fail :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end
    #:fail-fast end

    it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash]] >} }
  end

=begin
When success: return the block's returns
When raise:   return {Railway.fail!} or {Railway.pass!}
=end
  class WrapWithCustomEndsTest < Minitest::Spec
    Memo   = Module.new

    #:custom-handler
    class MyTransaction
      MyFailSignal = Class.new(Trailblazer::Activity::Signal)

      def self.call((ctx, flow_options), *, &block)
        yield # calls the wrapped steps
      rescue
        MyFailSignal
      end
    end
    #:custom-handler end

    #:custom
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Wrap( MyTransaction ) {
        step :update
        step :rehash
      },
        Output(:success) => End(:transaction_worked),
        Output(MyTransaction::MyFailSignal, :failure) => End(:transaction_failed)
      step :notify
      fail :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end
    #:custom end

    it do
      result = Memo::Create.( { seq: [] } )
      result.inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:transaction_worked>}
    end

    it do
      result = Memo::Create.( { seq: [], rehash_raise: true } )
      result.inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:transaction_failed>}
    end
  end

=begin
When success: return the block's returns
When raise:   return {Railway.pass!} and go "successful"
=end
  class WrapGoesIntoPassFromRescueTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          yield # calls the wrapped steps
        rescue
          [ Trailblazer::Operation::Railway.pass!, [ctx, {}] ]
        end
      end

      step :find_model
      step Wrap( HandleUnsafeProcess ) {
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

    it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
  end

=begin
When success: return the block's returns
When raise:   return {true} and go "successful"
You can also return booleans in wrap.
=end
  class WrapGoesIntoBooleanFromRescueTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          yield # calls the wrapped steps
        rescue
          ctx[:wrap_boolean_return_value] # can be true/false/nil
        end
      end

      step :find_model
      step Wrap( HandleUnsafeProcess ) {
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

    it "translates true returned form a wrap to a signal with a `success` semantic" do
      result = Memo::Create.( { seq: [], rehash_raise: true, wrap_boolean_return_value: true } )
      result.inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}
    end
    it "translates false returned form a wrap to a signal with a `failure` semantic" do
      result = Memo::Create.( { seq: [], rehash_raise: true, wrap_boolean_return_value: false } )
      result.inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Failure semantic=:failure>}
    end
    it "translates nil returned form a wrap to a signal with a `failure` semantic" do
      result = Memo::Create.( { seq: [], rehash_raise: true, wrap_boolean_return_value: nil } )
      result.inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Failure semantic=:failure>}
    end
  end

=begin
When success: return the block's returns
When raise:   return {Railway.fail!}
This one is mostly to show how one could wrap steps in a transaction
=end
  class WrapWithTransactionTest < Minitest::Spec
    Memo = Module.new

    module Sequel
      def self.transaction
        end_event, (ctx, flow_options) = yield
      end
    end

    #:transaction-handler
    class HandleUnsafeProcess
      def self.call((ctx, flow_options), *, &block)
        Sequel.transaction { yield } # calls the wrapped steps
      rescue
        [ Trailblazer::Operation::Railway.fail!, [ctx, flow_options] ]
      end
    end
    #:transaction-handler end

    #:transaction
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Wrap( HandleUnsafeProcess ) {
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
    #:transaction end

    it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >} }
  end
end
