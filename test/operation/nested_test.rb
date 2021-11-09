require 'test_helper'

class NestedTest < Minitest::Spec
  DatabaseError = Class.new(Trailblazer::Activity::Signal)

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
end
