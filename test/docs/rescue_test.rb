require "test_helper"

class NestedRescueTest < Minitest::Spec
  #---
  # nested raise (i hope people won't use this but it works)
  A = Class.new(RuntimeError)
  Y = Class.new(RuntimeError)

  class NestedInsanity < Trailblazer::Operation
    include T.def_steps(:a, :y, :outer_err, :z, :e, :b, :c, :inner_err)

    step Rescue() {
      step :a
      step Rescue() {
        step :y
        pass ->(ctx, **) { raise Y if ctx["raise-y"] }
        step :z
      }
      step :b
      pass ->(ctx, **) { raise A if ctx["raise-a"] }
      step :c
      left :inner_err
    }
    step :e, id: "nested/e"
    left :outer_err, id: "nested/failure"
  end

  it { assert_match /\[>Rescue\/[\d\.]+,>nested/, Trailblazer::Developer.railway(NestedInsanity)  } # FIXME: better introspect tests for all id-generating macros.
  it { assert_run NestedInsanity, seq: [:a, :y, :z, :b, :c, :e], terminus: :success }
  it { assert_run NestedInsanity, target_ctx: {"raise-y" => true, seq: []}, seq: [:a, :y, :inner_err, :outer_err], terminus: :failure }
  it { assert_run NestedInsanity, target_ctx: {"raise-a" => true, seq: []}, seq: [:a, :y, :z, :b, :outer_err], terminus: :failure }

  #-
  # inheritance
  class UbernestedInsanity < NestedInsanity
  end

  it { assert_run UbernestedInsanity, seq: [:a, :y, :z, :b, :c, :e], terminus: :success }
  it { assert_run UbernestedInsanity, target_ctx: {"raise-y" => true, seq: []}, seq: [:a, :y, :inner_err, :outer_err], terminus: :failure }
end



class RescueTest < Minitest::Spec

=begin
plain Rescue()
=end
  class RescueWithoutHandlerTest < Minitest::Spec
    Song = Class.new
    module Song::Activity; end

    #:no-args
    class Song::Activity::Create < Trailblazer::Operation
      step :create_model
      step Rescue() {
        step :upload
        step :rehash
      }
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:create_model, :upload, :notify, :log_error)
      include Rehash
      #~methods end
    end
    #:no-args end

    it { assert_run Song::Activity::Create, seq: [:create_model, :upload, :rehash, :notify], terminus: :success }
    it { assert_run Song::Activity::Create, target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :failure, seq: [:create_model, :upload, :rehash, :log_error] }
    it { assert_run Song::Activity::Create, target_ctx: {rehash_raise: :bla, seq: []}, terminus: :failure, seq: [:create_model, :upload, :rehash, :log_error] }
    it { assert_run Song::Activity::Create, target_ctx: {rehash_raise: NoMethodError, seq: []}, terminus: :failure, seq: [:create_model, :upload, :rehash, :log_error] }
  end

=begin
Rescue( SPECIFIC_EXCEPTION, handler: X )
=end
  class RescueWithClassHandlerTest < Minitest::Spec
    Song = Class.new
    module Song::Activity; end

    #:rescue-handler
    class MyHandler
      def self.call(ctx, exception:, **)
        ctx[:exception_class] = exception.class

        false
      end
    end
    #:rescue-handler end

    #:rescue
    class Song::Activity::Create < Trailblazer::Operation
      step :create_model
      step Rescue(RuntimeError, handler: MyHandler) {
        step :upload
        step :rehash
      }
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:create_model, :upload, :notify, :log_error)
      include Rehash
      # def log_error(ctx, **)
      #   raise ctx.inspect
      # end
      #~methods end
    end
    #:rescue end

    it { assert_run Song::Activity::Create, seq: [:create_model, :upload, :rehash, :notify], terminus: :success }
    it do
      lib_ctx, _ = assert_run Song::Activity::Create, target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :failure, seq: [:create_model, :upload, :rehash, :log_error]

      assert_equal lib_ctx, {
        target_ctx: {
          rehash_raise: RuntimeError,
          exception_class: RuntimeError,
          seq: [:create_model, :upload, :rehash, :log_error]
        }
      }
    end
    it do
      # Since we don't catch KeyError, execution stops.
      assert_raises KeyError do
        Song::Activity::Create.({seq: [], rehash_raise: KeyError})
      end
    end
  end

  # TODO: we don't leak :exception
  it "what" do
    raise
  end

  it "we can use {:lib_interface} for the rescue handler" do
    raise
  end

  class RescueWithModuleHandlerTest < Minitest::Spec
    Memo = Class.new

    module MyHandler
      def self.call(ctx, exception:, **)
        ctx[:exception_class] = exception.class

        false
      end
    end

    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Rescue( RuntimeError, handler: MyHandler ) {
        step :update
        step :rehash
      }
      step :notify
      left :log_error
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
    end

    it { assert_run Memo::Create, seq: [:find_model, :update, :rehash, :notify], terminus: :success }
    it do
      lib_ctx, _ = assert_run Memo::Create, target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :failure, seq: [:find_model, :update, :rehash, :log_error]

      assert_equal lib_ctx[:target_ctx][:exception_class], RuntimeError
    end
  end

=begin
Rescue( handler: :instance_method )
=end
  class RescueWithMethodHandlerTest < Minitest::Spec
    Memo = Class.new

    #:rescue-method
    class Memo::Create < Trailblazer::Operation
      step :find_model
      step Rescue(RuntimeError, handler: :my_handler) {
        step :update
        step :rehash
      }
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end

      def my_handler(ctx, exception:, **)
        ctx[:exception_class] = exception.class

        false
      end
    end
    #:rescue-method end

    it { assert_run Memo::Create, seq: [:find_model, :update, :rehash, :notify], terminus: :success }
    it do
      lib_ctx, _ = assert_run Memo::Create, target_ctx: {rehash_raise: RuntimeError, seq: []}, terminus: :failure, seq: [:find_model, :update, :rehash, :log_error]

      assert_equal lib_ctx[:target_ctx][:exception_class], RuntimeError
    end
  end

=begin
Rescue(), fast_track: true {}
=end
  class RescueWithFastTrack < Minitest::Spec
    Memo = Class.new

    #:rescue-fasttrack
    class Memo::Create < Trailblazer::Operation
      rescue_block = ->(*) {
        step :update, Output(:failure) => Terminus(:fail_fast)
        step :rehash
      }

      step :find_model
      step Rescue(&rescue_block), fail_fast: true, fast_track: true # FIXME: does fail_fast mean we want to connect both fail outputs automatically?
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error, :rehash)
    end

    # Trailblazer::Developer.puts(Memo::Create.config.circuit)
    # pp Memo::Create.config.circuit.flow_map

    it { assert_run Memo::Create, seq: [:find_model, :update, :rehash, :notify], terminus: :success }
    it { assert_run Memo::Create, target_ctx: {update: false, seq: []}, seq: [:find_model, :update], terminus: :fail_fast }
  end

  class RescueIDTest < Minitest::Spec
    class Validate
      def self.call(*)

      end
    end

    it "assigns ID via {Macro.id_for}" do
      activity = Class.new(Trailblazer::Activity::Railway) do
        step Rescue() {}
        step Rescue(handler: Validate) {}
        step Rescue(handler: :instance_method) {}
        step Rescue() {}, id: "Rescue-1"
        step Rescue(id: "Rescue-2") {}
        # test identical configuration.
        step Rescue() {}
        step Rescue(handler: Validate) {}
      end

      # assert_equal Trailblazer::Developer::Introspect.find_path(activity, ["Each/EachIDTest::Validate"])[0].id, "Each/EachIDTest::Validate"
      # assert_equal Trailblazer::Developer::Introspect.find_path(activity, ["Each-1"])[0].id,                    "Each-1"
      # assert_equal Trailblazer::Developer::Introspect.find_path(activity, ["Each/composers_for_each"])[0].id,   "Each/composers_for_each"

      assert_match (/Rescue\/\d+/), Trailblazer::Activity::Introspect::Nodes(activity).values[1].id
      assert_match (/Rescue\/\d+/), Trailblazer::Activity::Introspect::Nodes(activity).values[2].id
      assert_match (/Rescue\/\d+/), Trailblazer::Activity::Introspect::Nodes(activity).values[3].id
      assert_equal "Rescue-1", Trailblazer::Activity::Introspect::Nodes(activity).values[4].id
      assert_equal "Rescue-2", Trailblazer::Activity::Introspect::Nodes(activity).values[5].id
      assert_match (/Rescue\/\d+/), Trailblazer::Activity::Introspect::Nodes(activity).values[6].id
      assert_match (/Rescue\/\d+/), Trailblazer::Activity::Introspect::Nodes(activity).values[7].id
    end
  end

  class ComplianceTest < Minitest::Spec
    it "tracing" do
      activity = Class.new(Trailblazer::Activity::Railway) do
        step Rescue(id: "Rescue/1") {
          step :validate
        }

        def validate(ctx, validate: false, seq:, **)
          seq << :validate
          raise unless validate
          validate
        end
      end

      ctx = {validate: false}

      output, _ = trace activity, ctx

      assert_equal output, %(TOP
|-- Start.default
|-- Rescue/1
|   |-- Start.default
|   `-- validate
`-- End.failure)
    end
  end
end

=begin
Option#call implies we need an :exec_context kwarg, since we want to separate the circuit_options from the Options-specific parameters. E.g. what if the filter
calls another activity and needs the original circuit_options?

that means pure circuit_options filter are called differently from Option ones (the first don't receive kwargs)
=end


