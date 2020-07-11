require "test_helper"

class DocsModelTest < Minitest::Spec
  Song = Struct.new(:id, :title) do
    def self.find_by(args)
      key, value = args.flatten
      return nil if value.nil?
      return new(value) if key == :id
      new(2, value) if key == :title
    end

    def self.[](id)
      id.nil? ? nil : new(id+99)
    end
  end

  #:op
  class Create < Trailblazer::Operation
    step Model( Song, :new )
    # ..
  end
  #:op end

  it do
    #:create
    result = Create.(params: {})
    result[:model] #=> #<struct Song id=nil, title=nil>
    #:create end

    result[:model].inspect.must_equal %{#<struct DocsModelTest::Song id=nil, title=nil>}
  end


  #:update
  class Update < Trailblazer::Operation
    step Model( Song, :find_by )
    # ..
  end
  #:update end

  #:update-with-find-by-key
  class UpdateWithFindByKey < Trailblazer::Operation
    step Model( Song, :find_by, :title )
    # ..
  end
  #:update-with-find-by-key end

  #:update-with-not-found-end
  class UpdateFailureWithModelNotFound < Trailblazer::Operation
    step Model( Song, :find_by, not_found_terminus: true )
    # ..
  end
  #:update-with-not-found-end end

  it do
    #:update-ok
    result = Update.(params: { id: 1 })
    result[:model] #=> #<struct Song id=1, title="nil">
    #:update-ok end

    result[:model].inspect.must_equal %{#<struct DocsModelTest::Song id=1, title=nil>}
  end

  it do
    #:update-with-find-by-key-ok
    result = UpdateWithFindByKey.(params: { title: "Test" } )
    result[:model] #=> #<struct Song id=2, title="Test">
    #:update-with-find-by-key-ok end

    result[:model].inspect.must_equal %{#<struct DocsModelTest::Song id=2, title="Test">}
  end

  it do
    #:update-fail
    result = Update.(params: {})
    result[:model] #=> nil
    result.success? #=> false
    #:update-fail end
    result[:model].must_be_nil
    result.success?.must_equal false
  end

  it do
    #:update-with-find-by-key-fail
    result = UpdateWithFindByKey.(params: {title: nil})
    result[:model] #=> nil
    result.success? #=> false
    #:update-with-find-by-key-fail end
    result[:model].must_be_nil
    result.success?.must_equal false
  end

  it do
    #:update-with-not-found-end-use
    result = UpdateFailureWithModelNotFound.(params: {title: nil})
    result[:model] #=> nil
    result.success? #=> false
    result.event #=> #<Trailblazer::Activity::End semantic=:not_found>
    #:update-with-not-found-end-use end

    result[:model].must_be_nil
    result.success?.must_equal false
    result.event.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:not_found>}
  end

  #:show
  class Show < Trailblazer::Operation
    step Model( Song, :[] )
    # ..
  end
  #:show end

  it do
    result = Show.(params: { id: 1 })

    #:show-ok
    result = Show.(params: { id: 1 })
    result[:model] #=> #<struct Song id=1, title="Roxanne">
    #:show-ok end

    result.success?.must_equal true
    result[:model].inspect.must_equal %{#<struct DocsModelTest::Song id=100, title=nil>}
  end
end
