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

  it "Nested(Edit), without any options" do
    edit = self.edit

    create = Class.new(Trailblazer::Operation) do
      step :a
      step Nested( edit )
      step :b

      include T.def_steps(:a, :b)
    end

    # this will print a DEPRECATION warning.
  # success
    create.(seq: []).inspect(:seq).must_equal %{<Result:true [[:a, :c, :b]] >}
  # failure in Nested
    create.(seq: [], c: false).inspect(:seq).must_equal %{<Result:false [[:a, :c]] >}
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
    create = Class.new(Trailblazer::Operation) do
      step :a
      step Nested(:compute_edit)
      step :b

      def compute_edit(ctx, what:, **)
        what
      end

      include T.def_steps(:a, :b)
    end

    # `edit` and `update` can be called from Nested()

  # edit/success
    create.(seq: [], what: edit).inspect(:seq).must_equal %{<Result:true [[:a, :c, :b]] >}

  # update/success
    create.(seq: [], what: update).inspect(:seq).must_equal %{<Result:true [[:a, :d, :b]] >}


# wiring of fail:
  # edit/failure
    create.(seq: [], what: edit, c: false).inspect(:seq).must_equal %{<Result:false [[:a, :c]] >}
  # update/failure
    create.(seq: [], what: update, d: false).inspect(:seq).must_equal %{<Result:false [[:a, :d]] >}
  end
end

