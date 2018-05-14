require "test_helper"

class NestedInput < Minitest::Spec
  #:input-multiply
  class Multiplier < Trailblazer::Operation
    step ->(options, x:, y:, **) { options["product"] = x*y }
  end
  #:input-multiply end

  #:input-pi
  class MultiplyByPi < Trailblazer::Operation
    step ->(options, **) { options["pi_constant"] = 3.14159 }
    step Nested( Multiplier, input: ->(options, **) do
      { "y" => options["pi_constant"],
        "x" => options["x"]
      }
    end )
  end
  #:input-pi end

  it { MultiplyByPi.("x" => 9).inspect("product").must_equal %{<Result:true [28.27431] >} }

  it do
    #:input-result
    result = MultiplyByPi.("x" => 9)
    result["product"] #=> [28.27431]
    #:input-result end
  end
end

class NestedInputCallable < Minitest::Spec
  Multiplier = NestedInput::Multiplier

  #:input-callable
  class MyInput
    def self.call(options, **)
      {
        "y" => options["pi_constant"],
        "x" => options["x"]
      }
    end
  end
  #:input-callable end

  #:input-callable-op
  class MultiplyByPi < Trailblazer::Operation
    step ->(options, **) { options["pi_constant"] = 3.14159 }
    step Nested( Multiplier, input: MyInput )
  end
  #:input-callable-op end

  it { MultiplyByPi.("x" => 9).inspect("product").must_equal %{<Result:true [28.27431] >} }
end

class NestedWithCallableAndInputTest < Minitest::Spec
  Memo = Struct.new(:title, :text, :created_by)

  class Memo::Upsert < Trailblazer::Operation
    step Nested( :operation_class, input: :input_for_create )

    def operation_class( ctx, ** )
      ctx[:id] ? Update : Create
    end

    # only let :title pass through.
    def input_for_create( ctx, ** )
      { title: ctx[:title] }
    end

    class Create < Trailblazer::Operation
      step :create_memo

      def create_memo( ctx, ** )
        ctx[:model] = Memo.new(ctx[:title], ctx[:text], :create)
      end
    end

    class Update < Trailblazer::Operation
      step :find_by_title

      def find_by_title( ctx, ** )
        ctx[:model] = Memo.new(ctx[:title], ctx[:text], :update)
      end
    end
  end

  it "runs Create without :id" do
    Memo::Upsert.( title: "Yay!" ).inspect(:model).
      must_equal %{<Result:true [#<struct NestedWithCallableAndInputTest::Memo title=\"Yay!\", text=nil, created_by=:create>] >}
  end

  it "runs Update without :id" do
    Memo::Upsert.( id: 1, title: "Yay!" ).inspect(:model).
      must_equal %{<Result:true [#<struct NestedWithCallableAndInputTest::Memo title=\"Yay!\", text=nil, created_by=:update>] >}
  end
end

# builder: Nested + deviate to left if nil / skip_track if true

#---
# automatic :name
class NestedNameTest < Minitest::Spec
  class Create < Trailblazer::Operation
    class Present < Trailblazer::Operation
      # ...
    end

    step Nested( Present )
    # ...
  end

  it { Operation::Inspect.(Create).must_equal %{[>Nested(NestedNameTest::Create::Present)]} }
end
