require "test_helper"

class NestedInput < Minitest::Spec
  let(:edit) do
    edit = Class.new(Trailblazer::Operation) do
      step :c

      include T.def_steps(:c)
    end
  end

  let(:update) do
    edit = Class.new(Trailblazer::Operation) do
      step :d
      include T.def_steps(:d)
    end
  end

  class Validate < Trailblazer::Operation
    step :validate
    # ... more steps ...
    include T.def_steps(:validate)
  end

  class JsonValidate < Validate
    step :json
    include T.def_steps(:json)
  end

  it "Nested(Edit), without any options" do
      module A

        create =
        #:nested
        class Create < Trailblazer::Operation
          step :create
          step Nested(Validate)
          step :save
          #~meths
          include T.def_steps(:create, :save)
          #~meths end
        end
        #:nested end

        # this will print a DEPRECATION warning.
      # success
        create.(seq: []).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}
      # failure in Nested
        create.(seq: [], validate: false).inspect(:seq).must_equal %{<Result:false [[:create, :validate]] >}
      end
  end

  it "Nested(Edit), with Output rewiring" do
    edit = self.edit

    create = Class.new(Trailblazer::Operation) do
      step :a
      step Nested( edit ), Output(:failure) => Track(:success)
      step :b

      include T.def_steps(:a, :b)
    end

  # success
    create.(seq: []).inspect(:seq).must_equal %{<Result:true [[:a, :c, :b]] >}
  # failure in Nested
    create.(seq: [], c: false).inspect(:seq).must_equal %{<Result:true [[:a, :c, :b]] >}
  end

  it "Nested(:method)" do
    module B
      create =
      #:nested-dynamic
      class Create < Trailblazer::Operation
        step :create
        step Nested(:compute_nested)
        step :save

        def compute_nested(ctx, params:, **)
          params.is_a?(Hash) ? Validate : JsonValidate
        end
        #~meths
        include T.def_steps(:create, :save)
        #~meths end
      end
      #:nested-dynamic end
    # `edit` and `update` can be called from Nested()

  # edit/success
    create.(seq: [], params: {}).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}

  # update/success
    create.(seq: [], params: nil).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :json, :save]] >}


# wiring of fail:
  # edit/failure
    create.(seq: [], params: {}, validate: false).inspect(:seq).must_equal %{<Result:false [[:create, :validate]] >}
  # update/failure
    create.(seq: [], params: nil, json: false).inspect(:seq).must_equal %{<Result:false [[:create, :validate, :json]] >}
    end
  end

  it "Nested(:method), input: :my_input" do
    module C
      #:nested-dynamic
      class Create < Trailblazer::Operation
        step :create
        step Nested(:compute_nested), input: ->(ctx, *) {{foo: :bar, seq: ctx[:seq]}}
        step :save

        def compute_nested(ctx, params:, **)
          params.is_a?(Hash) ? Validate : JsonValidate
        end

        #~meths
        include T.def_steps(:create, :save)
        #~meths end
      end
      #:nested-dynamic end

    # `edit` and `update` can be called from Nested()
    end

    C::Create.(seq: [], params: {}).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}
    C::Create.(seq: [], params: nil).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :json, :save]] >}
  end

  it "Nested(:method), with pass_fast returned from nested" do
    class JustPassFast < Trailblazer::Operation
      step :just_pass_fast, pass_fast: true
      include T.def_steps(:just_pass_fast)
    end

    module D

      create =
      #:nested-with-pass-fast
      class Create < Trailblazer::Operation

        def compute_nested(ctx, **)
          JustPassFast
        end

        step :create
        step Nested(:compute_nested)
        step :save
        #~meths
        include T.def_steps(:create, :save)
        #~meths end
      end
      #:nested-with-pass-fast end

      # pass fast
      create.(seq: []).inspect(:seq).must_equal %{<Result:true [[:create, :just_pass_fast, :save]] >}
    end
  end

  it "Nested(:method, auto_wire: *activities) with :pass_fast => End()" do
    module E
      SignUp = Class.new(Trailblazer::Operation) do
        step :p, pass_fast: true
        include T.def_steps(:p)
      end

      SignIn = Class.new(Trailblazer::Operation) do
        step :f, fail_fast: true
        include T.def_steps(:f)
      end

      #:nested-with-auto-wire
      class Create < Trailblazer::Operation
        step :a
        step Nested(:compute_nested, auto_wire: [SignUp, SignIn]), Output(:pass_fast) => End(:new_sign_up)
        step :b

        #~meths
        def compute_nested(ctx, what:, **)
          what
        end

        include T.def_steps(:a, :b)
        #~meths end
      end
      #:nested-with-auto-wire end

      result = Create.(seq: [], what: SignUp)

      result.inspect(:seq).must_equal %{<Result:false [[:a, :p]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:new_sign_up>}
    end
  end
end

# TODO: test with :input/:output, tracing
