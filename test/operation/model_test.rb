require "test_helper"

class ModelTest < Minitest::Spec
  Song = Struct.new(:id, :title) do
    def self.find(id); new(id) end
    def self.find_by(args)
      key, value = args.flatten
      return nil if value.nil?
      return new(value) if key == :id
      new(2, value) if key == :title
    end
  end

  #---
  # use Model semantics, no customizations.
  # class Create < Trailblazer::Operation
  class Create < Trailblazer::Operation
    step Trailblazer::Operation::Model( Song, :new )
  end

  # :new new.
  it { Create.(params: {})[:model].inspect.must_equal %{#<struct ModelTest::Song id=nil, title=nil>} }
  it do

    result = Create.(params: {})

    result[:model].inspect.must_equal %{#<struct ModelTest::Song id=nil, title=nil>}
  end

  # class Update < Create
  class Update < Trailblazer::Operation
    step Trailblazer::Operation::Model( Song, :find ), override: true
  end

  #---
  #- inheritance

  # :find it
  it { Update.(params: { id: 1 })[:model].inspect.must_equal %{#<struct ModelTest::Song id=1, title=nil>} }

  # inherited inspect is ok
  it { Trailblazer::Operation::Inspect.(Update).must_equal %{[>model.build]} }

  #---
  # :find_by, exceptionless.
  # class Find < Trailblazer::Operation
  class Find < Trailblazer::Operation
    step Trailblazer::Operation::Model Song, :find_by
    step :process

    def process(options, **); options["x"] = true end
  end

  # :find_by, exceptionless.
  # class FindByKey < Trailblazer::Operation
  class FindByKey < Trailblazer::Operation
    step Trailblazer::Operation::Model( Song, :find_by, :title )
    step :process

    def process(options, **); options["x"] = true end
  end

  # can't find model.
  #- result object, model
  it do
    Find.(params: {id: nil})["result.model"].failure?.must_equal true
    Find.(params: {id: nil})["x"].must_be_nil
    Find.(params: {id: nil}).failure?.must_equal true
  end

  #- result object, model
  it do
    Find.(params: {id: 9})["result.model"].success?.must_equal true
    Find.(params: {id: 9})["x"].must_equal true
    Find.(params: {id: 9})[:model].inspect.must_equal %{#<struct ModelTest::Song id=9, title=nil>}
  end

  # can't find model by title.
  #- result object, model
  it do
    FindByKey.(params: {title: nil})["result.model"].failure?.must_equal true
    FindByKey.(params: {title: nil})["x"].must_be_nil
    FindByKey.(params: {title: nil}).failure?.must_equal true
  end

  #- result object, model by title
  it do
    FindByKey.(params: {title: "Test"})["result.model"].success?.must_equal true
    FindByKey.(params: {title: "Test"})["x"].must_equal true
    FindByKey.(params: {title: "Test"})[:model].inspect.must_equal %{#<struct ModelTest::Song id=2, title="Test">}
  end
end
