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
You can return boolean true in wrap.
=end
  class WrapGoesIntoBooleanTrueFromRescueTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          yield # calls the wrapped steps
        rescue
          true
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
      result = Memo::Create.( { seq: [], rehash_raise: true } )
      result.inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}
    end
  end

=begin
When success: return the block's returns
When raise:   return {false} and go "failed"
You can return boolean false in wrap.
=end
  class WrapGoesIntoBooleanFalseFromRescueTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          yield # calls the wrapped steps
        rescue
          false
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

    it "translates false returned form a wrap to a signal with a `failure` semantic" do
      result = Memo::Create.( { seq: [], rehash_raise: true } )
      result.inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash, :log_error]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Failure semantic=:failure>}
    end
  end

=begin
When success: return the block's returns
When raise:   return {nil} and go "failed"
You can return nil in wrap.
=end
  class WrapGoesIntoNilFromRescueTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          yield # calls the wrapped steps
        rescue
          nil
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

    it "translates nil returned form a wrap to a signal with a `failure` semantic" do
      result = Memo::Create.( { seq: [], rehash_raise: true } )
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
    class MyTransaction
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
      step Wrap( MyTransaction ) {
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

=begin
When success: return {Railway.pass_fast!}
When failure: return {Railway.fail!}
This one is mostly to show how one could evaluate Wrap()'s return value based on Wrap() block's return
=end
  class WrapWithBlockReturnSignatureCheckTest < Minitest::Spec
    Memo = Module.new

    #:handler-with-signature-evaluator
    class HandleUnsafeProcess
      def self.call((_ctx, _flow_options), *, &block)
        signal, (ctx, flow_options) = yield
        evaluated_signal = if signal.to_h[:semantic] == :success
                            Trailblazer::Operation::Railway.pass_fast!
                          else
                            Trailblazer::Operation::Railway.fail!
                          end
        [ evaluated_signal, [ctx, flow_options] ]
      end
    end
    #:handler-with-signature-evaluator end

    #:transaction
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Wrap( HandleUnsafeProcess ) {
        step :update
      }, fast_track: true # because Wrap can return pass_fast! now
      step :notify
      fail :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      #~methods end
    end
    #:transaction end

    it { Memo::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update]] >} }
    it { Memo::Create.( { seq: [], update: false } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :log_error]] >} }
  end


  class WrapOperationWithCustomTerminus < Minitest::Spec
    Song = Module.new

    module Song::Activity
      class HandleUnsafeProcess
        def self.call((ctx), *, &block)
          yield # calls the wrapped steps
        rescue
          [ Trailblazer::Operation::Railway.fail_fast!, [ctx, {}] ]
        end
      end

      class Upload < Trailblazer::Activity::FastTrack
        step :find_model
        step Wrap(HandleUnsafeProcess) {
          step :send_request,
            Output(:failure) => End(:timeout__) # adds a terminus {End.timeout}
          # step :rehash
        },
          Output(:timeout__) => Track(:fail_fast)
        step :upload
        fail :log_error
        #~methods
        include T.def_steps(:find_model, :send_request, :upload, :log_error)
        #~methods end
      end
    end

    it do
    #@ success path
      assert_invoke Song::Activity::Upload, seq: "[:find_model, :send_request, :upload]"

      assert_invoke Song::Activity::Upload, send_request: false, seq: "[:find_model, :send_request]", terminus: :fail_fast
    end


    # it { Song::Create.( { seq: [] } ).inspect(:seq).must_equal %{<Result:true [[:find_model, :update, :rehash, :notify]] >} }
    # it { Song::Create.( { seq: [], rehash_raise: true } ).inspect(:seq).must_equal %{<Result:false [[:find_model, :update, :rehash]] >} }
  end
end
