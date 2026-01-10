require "test_helper"

class NestedRescueTest < Minitest::Spec
  #---
  # nested raise (i hope people won't use this but it works)
  A = Class.new(RuntimeError)
  Y = Class.new(RuntimeError)

  class NestedInsanity < Trailblazer::Operation
    include T.def_steps(:a, :y, :outer_err, :z, :e, :b, :c, :inner_err)

    step Rescue {
      step :a
      step Rescue {
        step :y
        pass ->(options, **) { raise Y if options["raise-y"] }
        step :z
      }
      step :b
      pass ->(options, **) { raise A if options["raise-a"] }
      step :c
      left :inner_err
    }
    step :e, id: "nested/e"
    left :outer_err, id: "nested/failure"
  end

  it { assert_match /\[>Rescue\/.{1,3},>nested/, Trailblazer::Developer.railway(NestedInsanity)  } # FIXME: better introspect tests for all id-generating macros.
  it { assert_invoke NestedInsanity, seq: "[:a, :y, :z, :b, :c, :e]" }
  it { assert_invoke NestedInsanity, "raise-y" => true, seq: "[:a, :y, :inner_err, :outer_err]", terminus: :failure }
  it { assert_invoke NestedInsanity, "raise-a" => true, seq: "[:a, :y, :z, :b, :outer_err]", terminus: :failure }

  #-
  # inheritance
  class UbernestedInsanity < NestedInsanity
  end

  it { assert_invoke UbernestedInsanity, seq: "[:a, :y, :z, :b, :c, :e]" }
  it { assert_invoke UbernestedInsanity, "raise-y" => true, seq: "[:a, :y, :inner_err, :outer_err]", terminus: :failure }
end

class RescueTest < Minitest::Spec

=begin
plain Rescue()
=end
  class RescueWithoutHandlerTest < Minitest::Spec
    Song = Class.new
    module Song::Activity; end

    #:no-args
    class Song::Activity::Create < Trailblazer::Activity::Railway
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

    it { assert_invoke Song::Activity::Create, seq: "[:create_model, :upload, :rehash, :notify]" }
    it { assert_invoke Song::Activity::Create, rehash_raise: RuntimeError, terminus: :failure, seq: "[:create_model, :upload, :rehash, :log_error]", exception_class: RuntimeError }
    it { assert_invoke Song::Activity::Create, rehash_raise: :bla, terminus: :failure, seq: "[:create_model, :upload, :rehash, :log_error]", exception_class: :bla }
    it { assert_invoke Song::Activity::Create, rehash_raise: NoMethodError, terminus: :failure, seq: "[:create_model, :upload, :rehash, :log_error]", exception_class: NoMethodError }
  end

=begin
Rescue( SPECIFIC_EXCEPTION, handler: X )
=end
  class RescueWithClassHandlerTest < Minitest::Spec
    Song = Class.new
    module Song::Activity; end

    #:rescue-handler
    class MyHandler
      def self.call(exception, (ctx), *)
        ctx[:exception_class] = exception.class
      end
    end
    #:rescue-handler end

    #:rescue
    class Song::Activity::Create < Trailblazer::Activity::Railway
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
      #~methods end
    end
    #:rescue end

    it { assert_invoke Song::Activity::Create, seq: "[:create_model, :upload, :rehash, :notify]" }
    it { assert_invoke Song::Activity::Create, rehash_raise: RuntimeError, terminus: :failure, seq: "[:create_model, :upload, :rehash, :log_error]", exception_class: RuntimeError }
    it do
      # Since we don't catch NoMethodError, execution stops.
      assert_raises NoMethodError do
        Song::Activity::Create.invoke([{seq: {}, rehash_raise: NoMethodError}])
      end
    end
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
      left :log_error
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
    end

    it { assert_invoke Memo::Create, seq: "[:find_model, :update, :rehash, :notify]" }
    it { assert_invoke Memo::Create, rehash_raise: RuntimeError, seq: "[:find_model, :update, :rehash, :log_error]", expected_ctx_variables: {exception_class: RuntimeError}, terminus: :failure }
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
      left :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
      #~methods end

      def my_handler(exception, (ctx), *)
        ctx[:exception_class] = exception.class
      end
    end
    #:rescue-method end

    it { assert_invoke Memo::Create, seq: "[:find_model, :update, :rehash, :notify]" }
    it { assert_invoke Memo::Create, rehash_raise: RuntimeError, seq: "[:find_model, :update, :rehash, :log_error]", expected_ctx_variables: {exception_class: RuntimeError}, terminus: :failure }
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
      left :log_error
      #~methods
      include T.def_steps(:find_model, :update, :notify, :log_error, :rehash)
    end

    it { assert_invoke Memo::Create, seq: "[:find_model, :update, :rehash, :notify]" }
    it { assert_invoke Memo::Create, update: false, seq: "[:find_model, :update]", terminus: :fail_fast }
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

class RescueDeprecateHandlerWithPositionalExceptionArgumentTest < Minitest::Spec
  Song = Class.new
  module Song::Operation; end

  #:rescue-handler-2-1
  class MyHandler
    def self.call(exception, (ctx), *)
      ctx[:seq] << :MyHandler
      ctx[:exception_class] = exception.class
    end
  end
  #:rescue-handler-2-1 end

  class Song::Operation::Create < Trailblazer::Activity::Railway
    step :create_model
    step :notify
    left :log_error
    #~methods
    include T.def_steps(:create_model, :upload, :notify, :log_error)
    include Rehash
    #~methods end
  end

  it do
    activity = nil
    _, warnings = capture_io do
      activity = Class.new(Trailblazer::Activity::Railway) do
        step Rescue(RuntimeError, handler: MyHandler) {
          step :rehash
        }
        include Rehash
      end
    end
    line_number_for_rescue = __LINE__ - 6

    # Deprecation warning at compile time.
    assert_equal warnings, %([Trailblazer] #{File.realpath(__FILE__)}:#{line_number_for_rescue} The Rescue() handler has a new interface, the old `(exception, (ctx), ..), **` signature is deprecated.
Please use (ctx, flow_options, circuit_options, exception:, **) , check ### FIXME _____---------------
)

    _, warnings = capture_io do
      assert_invoke activity, seq: "[:rehash]"
    end
    assert_equal warnings, ""

    # _, warnings = capture_io do
      assert_invoke activity, rehash_raise: RuntimeError, terminus: :failure, seq: "[:rehash, :MyHandler]", expected_ctx_variables: {exception_class: RuntimeError}
    # end
    assert_equal warnings, ""
  end
end

class RescueDeprecateInstanceMethodHandlerWithPositionalExceptionArgumentTest < Minitest::Spec
  Song = Class.new
  module Song::Operation; end


  class Song::Operation::Create < Trailblazer::Activity::Railway
    step Rescue(RuntimeError, handler: :my_handler) {
      step :upload
      step :rehash
    }

    #:rescue-handler-instance-method-2-1
    def my_handler(exception, (ctx), *)
    # def my_handler(ctx, flow_options, *, **)
      ctx[:seq] << :my_handler
      ctx[:exception_class] = exception.class
    end
    #:rescue-handler-instance-method-2-1 end
    #~methods
    include T.def_steps(:upload)
    include Rehash
    #~methods end
  end

  it {
    _, warnings = capture_io do
      assert_invoke Song::Operation::Create, seq: "[:upload, :rehash]"
    end

    assert_equal warnings, ""
  }

  it {
    _, warnings = capture_io do
      assert_invoke Song::Operation::Create, rehash_raise: RuntimeError, terminus: :failure, seq: "[:upload, :rehash, :my_handler]", expected_ctx_variables: {exception_class: RuntimeError}
    end

    assert_equal warnings, %([Trailblazer] RescueDeprecateInstanceMethodHandlerWithPositionalExceptionArgumentTest::Song::Operation::Create#my_handler The Rescue() handler has a new interface, the old `(exception, (ctx), ..), **` signature is deprecated.
Please use (ctx, flow_options, circuit_options, exception:, **) , check ### FIXME _____---------------\n)
  }
end

=begin
Option#call implies we need an :exec_context kwarg, since we want to separate the circuit_options from the Options-specific parameters. E.g. what if the filter
calls another activity and needs the original circuit_options?

that means pure circuit_options filter are called differently from Option ones (the first don't receive kwargs)
=end


