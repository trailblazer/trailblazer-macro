require "test_helper"

class DocsWrapTest < Minitest::Spec
  module Memo
  end

  module Methods
    def find_model(ctx, seq:, **)
      seq << :find_model
    end

    def update(ctx, seq:, **)
      seq << :update
    end

    def notify(ctx, seq:, **)
      seq << :notify
    end

    def rehash(ctx, seq:, rehash_raise:false, **)
      seq << :rehash
      raise if rehash_raise
      true
    end

    def log_error(ctx, seq:, **)
      seq << :log_error
    end
  end

=begin
When success: return the block's returns
When raise:   return {Railway.fail!}
=end
  #:wrap-handler
  class HandleUnsafeProcess
    def self.call((ctx, flow_options), *, &block)
      begin
        yield # calls the wrapped steps
      rescue
        [ Trailblazer::Operation::Railway.fail!, [ctx, flow_options] ]
      end
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
    include Methods
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
When success: return the block's returns
When raise:   return {Railway.fail!}, but wire Wrap() to {fail_fast: true}
=end
  class WrapGoesIntoFailFastTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          begin
            yield # calls the wrapped steps
          rescue
            [ Trailblazer::Operation::Railway.fail!, [ctx, {}] ]
          end
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
      include DocsWrapTest::Methods
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
        begin
          yield # calls the wrapped steps
        rescue
          [ Trailblazer::Operation::Railway.fail_fast!, [ctx, {}] ]
        end
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
      include DocsWrapTest::Methods
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
  class WrapWithTransactionTest < Minitest::Spec
    Memo = Module.new

    module Sequel
      def self.transaction
        begin
          end_event, (ctx, flow_options) = yield
          true
        rescue
          false
        end
      end
    end

    #:transaction-handler
    class MyTransaction
      def self.call((ctx, flow_options), *, &block)
        result = Sequel.transaction { yield }

        signal = result ? Trailblazer::Operation::Railway.pass! : Trailblazer::Operation::Railway.fail!

        [ signal, [ctx, flow_options] ]
      end
    end
    #:transaction-handler end

    #:transaction
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Wrap( MyTransaction ) {
        step :update
        step :rehash
      }
      step :notify
      fail :log_error
      #~methods
      include DocsWrapTest::Methods
      #~methods end
    end
    #:transaction end

    it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >} }
  end

=begin
When success: return the block's returns
When raise:   return {Railway.fail!} or {Railway.pass!}
=end
  class WrapWithCustomEndsTest < Minitest::Spec
    Memo   = Module.new
    Sequel = WrapWithTransactionTest::Sequel

    #:custom-handler
    class MyTransaction
      MyFailSignal = Class.new(Trailblazer::Activity::Signal)

      def self.call((ctx, flow_options), *, &block)
        result = Sequel.transaction { yield }

        signal = result ? Trailblazer::Operation::Railway.pass! : MyFailSignal

        [ signal, [ctx, flow_options] ]
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
      include DocsWrapTest::Methods
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
          begin
            yield # calls the wrapped steps
          rescue
            [ Trailblazer::Operation::Railway.pass!, [ctx, {}] ]
          end
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
      include DocsWrapTest::Methods
      #~methods end
    end

    it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    it { Memo::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
  end
end
