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

      class JsonValidate < Validate
        step :json
        include T.def_steps(:json)
      end
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

      class JsonValidate < Validate
        step :json
        include T.def_steps(:json)
      end

    # `edit` and `update` can be called from Nested()
    end

    C::Create.(seq: [], params: {}).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}
    C::Create.(seq: [], params: nil).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :json, :save]] >}
  end

  let(:compute_edit) {
    ->(ctx, what:, **) { what }
  }

  it "Nested(:method), :pass_fast => :fail_fast doesn't work with standard wiring" do
    skip "we need to allow adding :outputs"

    compute_edit = self.compute_edit

    pass_fast = Class.new(Trailblazer::Operation) do
      step :p, pass_fast: true
      include T.def_steps(:p)
    end

    create = Class.new(Trailblazer::Operation) do
      step :a
      step Nested(compute_edit, auto_wire: [pass_fast]), Output(:pass_fast) => Track(:fail_fast)
      step :b
      include T.def_steps(:a, :b)
    end


    create.(seq: [], what: pass_fast).inspect(:seq).must_equal %{<Result:false [[:a, :c]] >}
  end
end

# TODO: test with :input/:output, tracing
