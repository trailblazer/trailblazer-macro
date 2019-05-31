require "test_helper"

class NestedInput < Minitest::Spec
  let(:edit) do
    edit = Class.new(Trailblazer::Operation) do
      step :c

      include T.def_steps(:c)
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
end

