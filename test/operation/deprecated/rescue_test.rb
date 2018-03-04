require "test_helper"

class DeprecatedRescueTest < Minitest::Spec
  RecordNotFound = Class.new(RuntimeError)

  Song = Struct.new(:id, :title) do
    def self.find(id)
      raise if id == "RuntimeError!"
      id.nil? ? raise(RecordNotFound) : new(id)
    end

    def lock!
      true
    end
  end

  #:simple
  class Create < Trailblazer::Operation
    class MyContract < Reform::Form
      property :title
    end

    step Rescue() {
      step Model( Song, :find )
      step Contract::Build( constant: MyContract )
    }
    step Contract::Validate()
    step Contract::Persist( method: :sync )
  end
  #:simple end

  it { Create.( params: {id: 1, title: "Prodigal Son"} )["contract.default"].model.inspect.must_equal %{#<struct DeprecatedRescueTest::Song id=1, title="Prodigal Son">} }
  it { Create.( params: {id: nil} ).inspect(:model).must_equal %{<Result:false [nil] >} }

  #-
  # Rescue ExceptionClass, handler: ->(*) { }
  class WithExceptionNameTest < Minitest::Spec
  #
  class MyContract < Reform::Form
    property :title
  end
  #:name
  class Create < Trailblazer::Operation
    step Rescue( RecordNotFound, KeyError, handler: :rollback! ) {
      step Model( Song, :find )
      step Contract::Build( constant: MyContract )
    }
    step Contract::Validate()
    step Contract::Persist( method: :sync )

    def rollback!(exception, options)
      options["x"] = exception.class
    end
  end
  #:name end

    it { Create.( params: {id: 1, title: "Prodigal Son"} )["contract.default"].model.inspect.must_equal %{#<struct DeprecatedRescueTest::Song id=1, title="Prodigal Son">} }
    it { Create.( params: {id: 1, title: "Prodigal Son"} ).inspect("x").must_equal %{<Result:true [nil] >} }
    it { Create.( params: {id: nil} ).inspect(:model, "x").must_equal %{<Result:false [nil, DeprecatedRescueTest::RecordNotFound] >} }
    it { assert_raises(RuntimeError) { Create.( params: {id: "RuntimeError!"} ) } }
  end


  #-
  # cdennl use-case
  class CdennlRescueAndTransactionTest < Minitest::Spec
    module Sequel
      cattr_accessor :result

      def self.transaction
        yield.tap do |res|
          self.result = res
        end
      end
    end

  #:example
  class Create < Trailblazer::Operation
    class MyContract < Reform::Form
      property :title
    end

    class Rollback
      def self.call(exception, options)
        #~ex
        options["x"] = exception.class
        #~ex end
      end
    end

    step Rescue( RecordNotFound, handler: Rollback ) {
      step Wrap (->(*, &block) { Sequel.transaction do block.call end }) {
        step Model( Song, :find )
        step ->(options, *) { options[:model].lock! } # lock the model.
        step Contract::Build( constant: MyContract )
        step Contract::Validate( )
        step Contract::Persist( method: :sync )
      }
    }
    failure :error! # handle all kinds of errors.


    def error!(options, *)
      #~ex
      options["err"] = true
      #~ex end
    end
  end
  #:example end

    it { Create.( params: {id: 1, title: "Pie"} ).inspect(:model, "x", "err").must_equal %{<Result:true [#<struct DeprecatedRescueTest::Song id=1, title=\"Pie\">, nil, nil] >} }
    # raise exceptions in Model:
    it { Create.( params: {id: nil} ).inspect(:model, "x").must_equal %{<Result:false [nil, DeprecatedRescueTest::RecordNotFound] >} }
    it { assert_raises(RuntimeError) { Create.( params: {id: "RuntimeError!"} ) } }
    it do
      Create.( params: {id: 1, title: "Pie"} )
      Sequel.result.first.must_be_kind_of Trailblazer::Operation::Railway::End::Success
    end
  end
end
