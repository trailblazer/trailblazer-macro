require 'test_helper'

class NestedTest < Minitest::Spec
  DatabaseError = Class.new(Trailblazer::Activity::Signal)

  def trace(activity, ctx)
    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(activity, [ctx, {}])
    return Trailblazer::Developer::Trace::Present.(stack, node_options: {stack.to_a[0]=>{label: "TOP"}}).gsub(/:\d+/, ""), signal, ctx
  end

  module ComputeNested
    module_function

    def compute_nested(ctx, what:, **)
      what
    end
  end

  class SignUp < Trailblazer::Operation
    def self.b(ctx, **)
      ctx[:seq] << :b
      return DatabaseError
    end

    step method(:b), Output(DatabaseError, :db_error) => End(:db_error)
  end

  class SignIn < Trailblazer::Operation
    include T.def_steps(:c)
    step :c
  end

  it "allows connection with custom output of a nested activity" do
    create = Class.new(Trailblazer::Operation) do
      include T.def_steps(:a, :d)

      step :a
      step Nested(SignUp), Output(:db_error) => Track(:no_user)
      step :d, magnetic_to: :no_user
    end

    result = create.(seq: [])
    result.inspect(:seq).must_equal %{<Result:true [[:a, :b, :d]] >}
    result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}
  end

  it "allows connecting dynamically nested activities with custom output when auto wired" do
    create = Class.new(Trailblazer::Operation) do
      def compute_nested(ctx, what:, **)
        what
      end

      include T.def_steps(:a, :d)

      step :a
      step Nested(:compute_nested, auto_wire: [SignUp, SignIn]), Output(:db_error) => Track(:no_user)
      step :d, magnetic_to: :no_user
    end

    result = create.(seq: [], what: SignUp)
    result.inspect(:seq).must_equal %{<Result:true [[:a, :b, :d]] >}
    result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}
  end

  #@ unit test
  # TODO: make me a non-Operation test.
  it "allows using multiple Nested() per operation" do
    create = Class.new(Trailblazer::Operation) do
      def compute_nested(ctx, what:, **)
        what
      end

      step Nested(:compute_nested)
      step Nested(:compute_nested), id: :compute_nested_again
    end

    #@ we want both Nested executed
    result = create.(seq: [], what: SignIn)
    result.inspect(:seq).must_equal %{<Result:true [[:c, :c]] >}
    result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}

    result = create.wtf?(seq: [], what: SignUp)
    result.inspect(:seq).must_equal %{<Result:false [[:b]] >}
    result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Failure semantic=:failure>}
  end

  it "raises RuntimeError if dynamically nested activities with custom output are not auto wired" do
    exception = assert_raises RuntimeError do
      Class.new(Trailblazer::Operation) do
        def compute_nested(ctx, what:, **)
          what
        end

        step Nested(:compute_nested), Output(:db_error) => Track(:no_user)
      end
    end

    exception.inspect.must_match 'No `db_error` output found'
  end

  it "shows warning if `Nested()` is being used instead of `Subprocess()` for static activities" do
    _, warnings = capture_io do
      Class.new(Trailblazer::Operation) do
        step Nested(SignUp)
      end
    end

    warnings.must_equal %Q{[Trailblazer]#{__FILE__}: Using the `Nested()` macro with operations and activities is deprecated. Replace `Nested(NestedTest::SignUp)` with `Subprocess(NestedTest::SignUp)`.
}
  end

  it "{#wtf?} with Nested::Dynamic and {:decider} instance method" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      include T.def_steps(:a)
      include ComputeNested

      step :a
      step Nested(:compute_nested)
    end

  #@ SignIn, success
    output, signal, ctx = trace(activity, {seq: [], what: SignIn})
    assert_equal signal.inspect, %{#<Trailblazer::Activity::End semantic=:success>}
    assert_equal ctx.inspect, %{{:seq=>[:a, :c], :what=>NestedTest::SignIn, :nested_activity=>NestedTest::SignIn}}
    assert_equal output, %{TOP
|-- Start.default
|-- a
|-- Nested(compute_nested)
|   |-- Start.default
|   |-- #<Trailblazer::Activity::TaskBuilder::Task user_proc=compute_nested>
|   |-- call_dynamic_nested
|   |   `-- NestedTest::SignIn
|   |       |-- Start.default
|   |       |-- c
|   |       `-- End.success
|   `-- End.success
`-- End.success}

  #@ SignIn, failure
    output, signal, ctx = trace(activity, {seq: [], what: SignIn, c: false})
    assert_equal signal.inspect, %{#<Trailblazer::Activity::End semantic=:failure>}
    assert_equal ctx.inspect, %{{:seq=>[:a, :c], :what=>NestedTest::SignIn, :c=>false, :nested_activity=>NestedTest::SignIn}}
    assert_equal output, %{TOP
|-- Start.default
|-- a
|-- Nested(compute_nested)
|   |-- Start.default
|   |-- #<Trailblazer::Activity::TaskBuilder::Task user_proc=compute_nested>
|   |-- call_dynamic_nested
|   |   `-- NestedTest::SignIn
|   |       |-- Start.default
|   |       |-- c
|   |       `-- End.failure
|   `-- End.failure
`-- End.failure}
  end

  it "Nested() unit test" do
    my_decider  = ComputeNested.method(:compute_nested)
    activity    = Trailblazer::Macro.Nested(my_decider)[:task]

    ctx = {
      what: SignUp,
      seq: [],
    }

    # signal, (_ctx, _) = Trailblazer::Activity::TaskWrap.invoke(activity, [ctx])
    signal, (_ctx, _) = Trailblazer::Developer.wtf?(activity, [ctx], exec_context: self)
    assert_equal _ctx.inspect, %{{:what=>NestedTest::SignUp, :seq=>[:b], :nested_activity=>NestedTest::SignUp}}
  end
end

# TODO:  find_path in Nested
