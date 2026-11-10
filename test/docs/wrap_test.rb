require "test_helper"

#@ yield returns a circuit-interface result set, we can return it to the flow
#:my_transaction
# app/concepts/macro/my_transaction.rb
class MyTransaction
  def self.call(ctx, flow_options, signal, **circuit_options, &block)
    #:yield-and-return
                                # Run the wrapped steps.
    ctx, flow_options, signal = yield(ctx, flow_options, signal, **circuit_options)
    # maybe do something more?

    return ctx, flow_options, signal
    #:yield-and-return end
  end
end
#:my_transaction end

# TODO: add 2.1 version of the above

class WrapSimpleHandlerTest < Minitest::Spec
  MyTransaction = ::MyTransaction

  class Song
  end

  #:upload
  module Song::Activity
    class Upload < Trailblazer::Activity::FastTrack
      step :model
      step Wrap(MyTransaction) {
        step :update   # this changes the database.
        step :transfer # this might even break!
      }
      step :notify
      left :log_error
      #~meths
      include T.def_steps(:model, :update, :transfer, :notify, :log_error)
      #~meths end
    end
  end
  #:upload end

  it do
  #@ happy days
    assert_run Song::Activity::Upload, seq: [:model, :update, :transfer, :notify], terminus: :success
  #@ transfer returns false
    assert_run Song::Activity::Upload, target_ctx: {transfer: false, seq: []}, seq: [:model, :update, :transfer, :log_error],
      terminus: :failure
  end
end

class WrapSimpleHandlerRoutesCustomTerminsTest < Minitest::Spec
  MyTransaction = WrapSimpleHandlerTest::MyTransaction

  class Song
  end

  module Song::Activity
    class Upload < Trailblazer::Activity::FastTrack
      step :model
      #:out
      #:out-wrap
      step Wrap(MyTransaction) {
        step :update   # this changes the database.
        step :transfer,
          Output(:failure) => Terminus(:timeout) # creates a third terminus.
      },
      #:out-wrap end
        Output(:timeout) => Track(:fail_fast) # any wiring is possible here.
      #:out end
      step :notify
      left :log_error
      #~meths
      include T.def_steps(:model, :update, :transfer, :notify, :log_error)
      #~meths end
    end
  end

  it do
  #@ happy days
    assert_run Song::Activity::Upload, seq: [:model, :update, :transfer, :notify], terminus: :success
  #@ transfer returns false
    assert_run Song::Activity::Upload, target_ctx: {transfer: false, seq: []}, seq: [:model, :update, :transfer],
      terminus: :fail_fast
  #@ update returns false
    assert_run Song::Activity::Upload, target_ctx: {update: false, seq: []}, seq: [:model, :update, :log_error],
      terminus: :failure
  end
end

#@ handler uses rescue. Pretty sure we got identical tests below.
class WrapMyRescueTest < Minitest::Spec
  #:my_rescue
  class MyRescue
    def self.call(ctx, flow_options, signal, **circuit_options, &block)
      ctx, flow_options, signal = yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps

      return ctx, flow_options, signal
    rescue
      ctx[:target_ctx][:exception] = $!.message
      return ctx, flow_options, Trailblazer::Activity::Left
    end
  end
  #:my_rescue end

  class Song
  end

  #:upload-rescue
  module Song::Activity
    class Upload < Trailblazer::Activity::FastTrack
      step :model
      step Wrap(MyRescue, id: :my_rescue) {
        step :update
        step :transfer # might raise an exception.
      }
      step :notify
      left :log_error
      #~meths
      include T.def_steps(:model, :update, :transfer, :notify, :log_error)

      def transfer(ctx, seq:, transfer: true, **)
        seq << :transfer
        raise RuntimeError.new("transfer failed") unless transfer
        transfer
      end
      #~meths end
    end
  end
  #:upload-rescue end

  it do
  #@ happy days
    assert_run Song::Activity::Upload, seq: [:model, :update, :transfer, :notify], terminus: :success
  #@ transfer raises
    lib_ctx, _ = assert_run Song::Activity::Upload, target_ctx: {transfer: false, seq: []}, seq: [:model, :update, :transfer, :log_error],
      terminus: :failure

    assert_equal lib_ctx[:target_ctx], {transfer: false, seq: [:model, :update, :transfer, :log_error], exception: "transfer failed"}
  end
end

class DocsWrapTest < Minitest::Spec
=begin
When success: return the block's returns
When raise:   return {Railway.fail!}
=end
  #:wrap-handler
  class HandleUnsafeProcess
    def self.call(ctx, flow_options, signal, **circuit_options, &block)
      ctx, flow_options, signal = yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps

      return ctx, flow_options, signal
    rescue
      ctx[:target_ctx][:exception] = $!.message

      return ctx, flow_options, Trailblazer::Operation.fail!
    end
  end
  #:wrap-handler end

  #:wrap
  class Memo::Create < Trailblazer::Operation
    step :model
    step Wrap(HandleUnsafeProcess) {
      step :update
      step :rehash
    }
    step :notify
    left :log_error
    #~methods
    include T.def_steps(:model, :update, :notify, :log_error)
    include Rehash
    #~methods end
  end
  #:wrap end

  it do
  #@ happy days
    assert_run Memo::Create, seq: [:model, :update, :rehash, :notify], terminus: :success
  #@ rehash raises
    assert_run Memo::Create, target_ctx: {rehash_raise: RuntimeError, seq: []}, seq: [:model, :update, :rehash, :log_error],
      terminus: :failure,
      expected_ctx_variables: {exception: "RuntimeError"}
  end

=begin
When success: return the block's returns
When raise:   return {Railway.fail!}, but wire Wrap() to {fail_fast: true}
=end
  class WrapGoesIntoFailFastTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call(ctx, flow_options, signal, **circuit_options, &block)
          yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps
        rescue
          return ctx, flow_options, Trailblazer::Operation.fail!
        end
      end

      step :model
      step Wrap(HandleUnsafeProcess) {
        step :update
        step :rehash
      }, fail_fast: true
      step :notify
      left :log_error

      #~methods
      include T.def_steps(:model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end

    it { assert_run Memo::Create, seq: [:model, :update, :rehash, :notify], terminus: :success }
    it { assert_run Memo::Create, seq: [:model, :update, :rehash], target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :fail_fast }
  end

=begin
When success: return the block's returns
When raise:   return {Railway.fail_fast!} and configure Wrap() to {fast_track: true}
=end
  class WrapGoesIntoFailFastViaFastTrackTest < Minitest::Spec
    Memo = Module.new

    #:fail-fast-handler
    class HandleUnsafeProcess
      def self.call(ctx, flow_options, signal, **circuit_options, &block)
        yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps
      rescue
        [ctx, flow_options, Trailblazer::Operation.fail_fast!]
      end
    end
    #:fail-fast-handler end

    #:fail-fast
    class Memo::Create < Trailblazer::Operation
      step :model
      step Wrap( HandleUnsafeProcess ) {
        step :update
        step :rehash
      }, fast_track: true
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end
    #:fail-fast end

    it { assert_run Memo::Create, seq: [:model, :update, :rehash, :notify], terminus: :success }
    it { assert_run Memo::Create, seq: [:model, :update, :rehash], target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :fail_fast }
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

      def self.call(ctx, flow_options, signal, **circuit_options, &block)
        yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps
      rescue
        return ctx, flow_options, MyFailSignal
      end
    end
    #:custom-handler end

    #:custom
    class Memo::Create < Trailblazer::Operation
      step :model
      step Wrap( MyTransaction ) {
        step :update
        step :rehash
      },
        Output(:success) => Terminus(:transaction_worked),
        Output(:failure, signal: MyTransaction::MyFailSignal) => Terminus(:transaction_failed)
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end
    #:custom end

    it { assert_run Memo::Create, seq: [:model, :update, :rehash], terminus: :transaction_worked }
    it { assert_run Memo::Create, seq: [:model, :update, :rehash], target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :transaction_failed }
  end

=begin
When success: return the block's returns
When raise:   return {Railway.pass!} and go "successful"
=end
  class WrapGoesIntoPassFromRescueTest < Minitest::Spec
    Memo = Module.new

    class Memo::Create < Trailblazer::Operation
      class HandleUnsafeProcess
        def self.call(ctx, flow_options, signal, **circuit_options, &block)
          yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps
        rescue
          return ctx, flow_options, Trailblazer::Operation.pass!
        end
      end

      step :model
      step Wrap( HandleUnsafeProcess ) {
        step :update
        step :rehash
      }
      step :notify
      left :log_error

      #~methods
      include T.def_steps(:model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end

    it { assert_run Memo::Create, seq: [:model, :update, :rehash, :notify], terminus: :success }
    it { assert_run Memo::Create, seq: [:model, :update, :rehash, :notify], target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :success }
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
        def self.call(ctx, flow_options, signal, **circuit_options, &block)
          yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps
        rescue
          return ctx, flow_options, Trailblazer::Activity::Right
        end
      end

      step :model
      step Wrap( HandleUnsafeProcess ) {
        step :update
        step :rehash
      }
      step :notify
      left :log_error

      #~methods
      include T.def_steps(:model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end

    it "translates true returned form a wrap to a signal with a `success` semantic" do
      assert_run Memo::Create, seq: [:model, :update, :rehash, :notify], target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :success
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
        def self.call(ctx, flow_options, signal, **circuit_options, &block)
          yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps
        rescue
          return ctx, flow_options, Trailblazer::Activity::Left
        end
      end

      step :model
      step Wrap( HandleUnsafeProcess ) {
        step :update
        step :rehash
      }
      step :notify
      left :log_error

      #~methods
      include T.def_steps(:model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end

    it "translates false returned form a wrap to a signal with a `failure` semantic" do
      assert_run Memo::Create, seq: [:model, :update, :rehash, :log_error], target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :failure
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
        _ctx, _flow_options, _terminus = yield
      end
    end

    #:transaction-handler
    class MyTransaction
      def self.call(ctx, flow_options, signal, **circuit_options, &block)
        Sequel.transaction { yield(ctx, flow_options, signal, **circuit_options) } # calls the wrapped steps
      rescue
        return ctx, flow_options, Trailblazer::Operation.fail!
      end
    end
    #:transaction-handler end

    #:transaction
    class Memo::Create < Trailblazer::Operation
      step :model
      step Wrap( MyTransaction ) {
        step :update
        step :rehash
      }
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:model, :update, :notify, :log_error)
      include Rehash
      #~methods end
    end
    #:transaction end

    it { assert_run Memo::Create, seq: [:model, :update, :rehash, :notify], terminus: :success }
    it { assert_run Memo::Create, seq: [:model, :update, :rehash, :log_error], target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :failure }
  end

=begin
When success: return {Railway.pass_fast!}
When failure: return {Railway.fail!}
This one is mostly to show how one could evaluate Wrap()'s return value based on Wrap() block's return
=end
  class WrapWithBlockReturnSignatureCheckTest < Minitest::Spec
    Memo = Module.new
    module Memo::Operation
    end

    #:handler-with-signature-evaluator
    class HandleUnsafeProcess
      def self.call(ctx, flow_options, signal, **circuit_options, &block)
        ctx, flow_options, signal = yield(ctx, flow_options, signal, **circuit_options)
        evaluated_signal = if signal.to_h[:semantic] == :success
                            Trailblazer::Operation.pass_fast!
                          else
                            Trailblazer::Operation.fail!
                          end

        return ctx, flow_options, evaluated_signal
      end
    end
    #:handler-with-signature-evaluator end

    #:transaction
    module Memo::Operation
      class Create < Trailblazer::Operation
        step :model
        step Wrap(HandleUnsafeProcess) {
          step :update
        }, fast_track: true # because Wrap can return pass_fast! now
        step :notify
        left :log_error
        #~methods
        include T.def_steps(:model, :update, :notify, :log_error)
        #~methods end
      end
    end
    #:transaction end

    it { assert_run Memo::Operation::Create, seq: [:model, :update], terminus: :pass_fast }
    it { assert_run Memo::Operation::Create, seq: [:model, :update, :log_error], target_ctx: {update: false, seq: []}, terminus: :failure }
  end

  class WrapOperationWithCustomTerminus < Minitest::Spec
    Song = Module.new

    module Song::Activity
      class HandleUnsafeProcess
        def self.call(ctx, flow_options, signal, **circuit_options, &block)
          yield(ctx, flow_options, signal, **circuit_options) # calls the wrapped steps
        rescue
          return ctx, flow_options, Trailblazer::Operation.fail_fast!
        end
      end

      class Upload < Trailblazer::Activity::FastTrack
        step :model
        step Wrap(HandleUnsafeProcess) {
          step :send_request,
            Output(:failure) => Terminus(:timeout__) # adds a terminus {End.timeout}
          # step :rehash
        },
          Output(:timeout__) => Track(:fail_fast)
        step :upload
        left :log_error
        #~methods
        include T.def_steps(:model, :send_request, :upload, :log_error)
        #~methods end
      end
    end

    it do
    #@ success path
      assert_run Song::Activity::Upload, seq: [:model, :send_request, :upload], terminus: :success
    #@ we travel through {:timeout}
      assert_run Song::Activity::Upload, seq: [:model, :send_request], target_ctx: {send_request: failure, seq: []}, terminus: :fail_fast
    end

    it "tracing" do
      assert_equal trace(Song::Activity::Upload, {seq: []})[0], %{TOP
|-- Start.default
|-- model
|-- Wrap/DocsWrapTest::WrapOperationWithCustomTerminus::Song::Activity::HandleUnsafeProcess
|   |-- Start.default
|   |-- send_request
|   `-- End.success
|-- upload
`-- End.success}

  #@ compile time
  #@ make sure we can find tasks/compile-time artifacts in Wrap by using their {compile_id}.
    # assert_equal Trailblazer::Developer::Introspect.find_path(Song::Activity::Upload,
    #   [Wrap])[0].task.inspect,
    #   %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=compute_item>}
    # puts Trailblazer::Developer::Render::TaskWrap.(activity, ["Each/1", "Each.iterate.block", "invoke_block_activity", :compute_item])

    end
  end
end

class WrapUnitTest < Minitest::Spec
  class HandleUnsafeProcess
    def self.call(ctx, flow_options, circuit_options, &block)
      yield(ctx, flow_options, circuit_options) # calls the wrapped steps
    end
  end

  it "assigns IDs via {Macro.id_for}" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      def self.my_wrap_handler(ctx, flow_options, circuit_options, &block)
        yield(ctx, flow_options, circuit_options) # calls the wrapped steps
      end

      my_wrap_handler = ->(ctx, flow_options, circuit_options, &block) do
        block.call(ctx, flow_options, circuit_options) # calls the wrapped steps
      end

      step Wrap(HandleUnsafeProcess) {}
      # step Wrap(:my_wrap_handler) {} # FIXME: this doesn't work, yet.
      step Wrap(method(:my_wrap_handler)) {}
      step Wrap(my_wrap_handler) {}, id: "proc:my_wrap_handler"
    end

    [
      "Wrap/WrapUnitTest::HandleUnsafeProcess",
      "Wrap/method(:my_wrap_handler)",
      "proc:my_wrap_handler"
    ].each do |id|
      assert_equal Trailblazer::Developer::Introspect.find_path(activity, [id])[0].id, id
    end

    assert_equal trace(activity, {seq: []})[0], %{TOP
|-- Start.default
|-- Wrap/WrapUnitTest::HandleUnsafeProcess
|   |-- Start.default
|   `-- End.success
|-- Wrap/method(:my_wrap_handler)
|   |-- Start.default
|   `-- End.success
|-- proc:my_wrap_handler
|   |-- Start.default
|   `-- End.success
`-- End.success}
  end

  it "complies with Introspect API/Patch API" do
    class MyValidation < Trailblazer::Activity::Railway
      step :validate
      include T.def_steps(:validate)
    end

    activity = Class.new(Trailblazer::Activity::Railway) do
      step Wrap(HandleUnsafeProcess) {
        step Subprocess(MyValidation), id: :validation
      }
    end

    mock_validation = ->(ctx, seq:, **) { ctx[:seq] = seq + [:mock_validation] }

    #@ Introspect::TaskMap  interface
    assert_equal CU.strip(Trailblazer::Developer::Introspect.find_path(activity,
      ["Wrap/WrapUnitTest::HandleUnsafeProcess", :validation, :validate])[0].task.inspect),
      %(#<Trailblazer::Activity::Circuit::Step::Binary:0x @step=#<Trailblazer::Activity::Circuit::Step::Option:0x @step=#<Trailblazer::Activity::Option::InstanceMethod:0x @filter=:validate>>>)

    #@ Patch interface
    patched_activity = Trailblazer::Activity::DSL::Linear::Patch.call(
      activity,
      ["Wrap/WrapUnitTest::HandleUnsafeProcess"],
      -> { step mock_validation, replace: :validation, id: :validation }
    )

    #@ the original activity with Wrap is unchanged.
    assert_invoke activity, seq: %{[:validate]}

    #@ the patched version only runs {mock_validation}.
    assert_invoke patched_activity, seq: %{[:mock_validation]}

    # Patch Wrap/Subprocess/step, put step after {validate}
    patched_activity = Trailblazer::Activity::DSL::Linear::Patch.call(
      activity,
      ["Wrap/WrapUnitTest::HandleUnsafeProcess", :validation],
      -> { step mock_validation }
    )

    #@ the original activity with Wrap is unchanged.
    assert_invoke activity, seq: %{[:validate]}

    #@ the patched version only runs {mock_validation}.
    assert_invoke patched_activity, seq: %{[:validate, :mock_validation]}
  end
end

class WrapStrategyComplianceTest < Minitest::Spec
  Song = WrapSimpleHandlerTest::Song

  it do
    #:patch
    upload_with_upsert = Trailblazer::Activity::DSL::Linear::Patch.call(
      Song::Activity::Upload,
      ["Wrap/MyTransaction"],
      -> { step :upsert, replace: :update }
    )
    #:patch end
    upload_with_upsert.include(T.def_steps(:upsert))

  #@ Original class isn't changed.
    assert_invoke Song::Activity::Upload, seq: "[:model, :update, :transfer, :notify]"
  #@ Patched class runs
    assert_invoke upload_with_upsert, seq: "[:model, :upsert, :transfer, :notify]"
  end

  it "find_path" do
    assert_equal CU.strip(Trailblazer::Developer::Introspect.find_path(Song::Activity::Upload,
      ["Wrap/MyTransaction", :transfer])[0].task.inspect),
      %(#<Trailblazer::Activity::Circuit::Step::Binary:0x @step=#<Trailblazer::Activity::Circuit::Step::Option:0x @step=#<Trailblazer::Activity::Option::InstanceMethod:0x @filter=:transfer>>>)

=begin
#:find_path
node, _ = Trailblazer::Developer::Introspect.find_path(
  Song::Activity::Upload,
  ["Wrap/MyTransaction", :transfer])
#=> #<Node ...>
#:find_path end
=end
  end

  it "tracing" do
    # Trailblazer::Developer.wtf?(Song::Activity::Upload, {seq: []})
  end
end
