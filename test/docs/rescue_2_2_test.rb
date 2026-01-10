require "test_helper"

# Test the {circuit_interface: true} behavior, starting with TRB 2.2.
class Rescue_2_2_MyHandler_callable_Test < Minitest::Spec
  # app/concepts/operation/rescue/my_handler.rb
  class MyHandler
    def self.call(ctx, flow_options, *, exception:)
      # handle the error
      ctx[:exception_class] = exception.class

      return ctx, flow_options, Trailblazer::Activity::Left
    end
  end

  class Song; end
  #:callable
  module Song::Operation
    class Create < Trailblazer::Activity::Railway
      step :create_model
      step Rescue(handler: MyHandler, circuit_interface: true) {
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
  end
  #:callable end

  it { assert_invoke Song::Operation::Create, seq: "[:create_model, :upload, :rehash, :notify]" }
  it { assert_invoke Song::Operation::Create, rehash_raise: RuntimeError, seq: "[:create_model, :upload, :rehash, :log_error]", expected_ctx_variables: {exception_class: RuntimeError}, terminus: :failure }

  it "doesn't warn about anything deprecated" do
    _, warnings = capture_io do
      assert_invoke Song::Operation::Create, rehash_raise: RuntimeError, seq: "[:create_model, :upload, :rehash, :log_error]", expected_ctx_variables: {exception_class: RuntimeError}, terminus: :failure
    end

    assert_equal warnings, ""
  end
end

class Rescue_2_2_callable_returns_signal_Test < Minitest::Spec
  class CloudUploadError < RuntimeError
  end

  # app/concepts/operation/rescue/my_handler.rb
  class MyHandler
    def self.call(ctx, flow_options, *, exception:)
      # handle the error
      if exception.is_a?(CloudUploadError)
        return ctx, flow_options, :CloudErrorSignal
      end

      return ctx, flow_options, Trailblazer::Activity::Left
    end
  end

  class Song; end
  #:callable-routing
  module Song::Operation
    class Create < Trailblazer::Activity::Railway
      step :create_model
      step Rescue(handler: MyHandler, circuit_interface: true) {
        step :upload
        step :rehash
      },
        Output(:CloudErrorSignal, :upload_failure) => End(:fail_fast)
      step :notify
      left :log_error
      #~methods
      include T.def_steps(:create_model, :upload, :notify, :log_error)
      include Rehash
      #~methods end
    end
  end
  #:callable-routing end

  it { assert_invoke Song::Operation::Create, seq: "[:create_model, :upload, :rehash, :notify]" }
  it { assert_invoke Song::Operation::Create, rehash_raise: RuntimeError, seq: "[:create_model, :upload, :rehash, :log_error]", terminus: :failure }
  it { assert_invoke Song::Operation::Create, rehash_raise: CloudUploadError, seq: "[:create_model, :upload, :rehash]", terminus: :fail_fast }
end
