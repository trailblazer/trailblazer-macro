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

  it { assert_match /\[>Rescue\/.{1,3},>nested/ , Trailblazer::Developer.railway(NestedInsanity) }
  it { assert_equal "<Result:true [true, true, true, true, true, true, nil, nil] >", NestedInsanity.().inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err") }
  it { assert_equal "<Result:false [true, true, nil, nil, nil, nil, true, true] >", NestedInsanity.( "raise-y" => true).inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err") }
  it { assert_equal "<Result:false [true, true, true, true, nil, nil, nil, true] >", NestedInsanity.( "raise-a" => true).inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err") }

  #-
  # inheritance
  class UbernestedInsanity < NestedInsanity
  end

  it { assert_equal "<Result:true [true, true, true, true, true, true, nil, nil] >", UbernestedInsanity.().inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err") }
  it { assert_equal "<Result:false [true, true, true, true, nil, nil, nil, true] >", UbernestedInsanity.( "raise-a" => true).inspect("a", "y", "z", "b", "c", "e", "inner-err", "outer-err") }
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
      fail :log_error
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
      fail :log_error
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
      fail :log_error
      include T.def_steps(:find_model, :update, :notify, :log_error)
      include Rehash
    end

    it { assert_equal Memo::Create.( { seq: [], } ).inspect(:seq, :exception_class), %{<Result:true [[:find_model, :update, :rehash, :notify], nil] >} }
    it { assert_equal Memo::Create.( { seq: [], rehash_raise: RuntimeError } ).inspect(:seq, :exception_class), %{<Result:false [[:find_model, :update, :rehash, :log_error], RuntimeError] >} }
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

    it do
      result = Memo::Create.( { seq: [] } )
      assert_equal "<Result:true [[:find_model, :update, :rehash, :notify], nil] >", result.inspect(:seq, :exception_class)
    end

    it do
      result = Memo::Create.( { seq: [], rehash_raise: RuntimeError } )
      assert_equal "<Result:false [[:find_model, :update, :rehash, :log_error], RuntimeError] >", result.inspect(:seq, :exception_class)
    end  end

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

    it { assert_equal "<Result:true [[:find_model, :update, :rehash, :notify]] >", Memo::Create.({ seq: [], }).inspect(:seq) }

    it { assert_equal "<Result:false [[:find_model, :update]] >", Memo::Create.({ seq: [], update: false }).inspect(:seq) }

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

      assert_match(/Rescue\/\d+/, Trailblazer::Activity::Introspect::Nodes(activity).values[1].id)
      assert_match(/Rescue\/\d+/, Trailblazer::Activity::Introspect::Nodes(activity).values[2].id)
      assert_match(/Rescue\/\d+/, Trailblazer::Activity::Introspect::Nodes(activity).values[3].id)
      assert_match "Rescue-1", Trailblazer::Activity::Introspect::Nodes(activity).values[4].id
      assert_match "Rescue-2", Trailblazer::Activity::Introspect::Nodes(activity).values[5].id
      assert_match(/Rescue\/\d+/, Trailblazer::Activity::Introspect::Nodes(activity).values[6].id)
      assert_match(/Rescue\/\d+/, Trailblazer::Activity::Introspect::Nodes(activity).values[7].id)
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
