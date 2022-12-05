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
    step Model(Song, :new)
    # ..
  end
  #:op end


  it "defaults {:params} to empty hash when not passed" do
    result = Create.({})
    assert_equal true, result.success?
    assert_equal %{#<struct DocsModelTest::Song id=nil, title=nil>}, result[:model].inspect

    result = Update.({})
    assert_equal false, result.success?
    assert_equal "nil", result[:model].inspect
  end

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

  it "allows injecting {:model.class} and friends" do
    class Hit < Song
    end

    #:di-model-class
    result = Create.(params: {}, :"model.class" => Hit)
    #:di-model-class end

    result[:model].inspect.must_equal %{#<struct DocsModelTest::Hit id=nil, title=nil>}

  # inject all variables
    #:di-all
    result = Create.(
      params:               {title: "Olympia"}, # some random variable.
      "model.class":        Hit,
      "model.action":       :find_by,
      "model.find_by_key": :title
    )
    #:di-all end

    result[:model].inspect.must_equal %{#<struct DocsModelTest::Hit id=2, title="Olympia">}

  # use empty Model() and inject {model.class} and {model.action}
    module A
      #:op-model-empty
      class Create < Trailblazer::Operation
        step Model()
        # ..
      end
      #:op-model-empty end
    end # A

    result = A::Create.(params: {}, :"model.class" => Hit)

    result[:model].inspect.must_equal %{#<struct DocsModelTest::Hit id=nil, title=nil>}


  end

  it "allows to use composable I/O with macros" do
    module AA
      #:in
      class Create < Trailblazer::Operation
        step Model(Song, :find_by),
          In() => ->(ctx, my_id:, **) { ctx.merge(params: {id: my_id}) } # Model() needs {params[:id]}.
        # ...
      end
      #:in end

      result = AA::Create.(my_id: 1)
=begin
#:in-call
result = Create.(my_id: 1)
#:in-call end
=end

    result[:model].inspect.must_equal %{#<struct DocsModelTest::Song id=1, title=nil>}

    end
  end
end

class Model404TerminusTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)
  #:update-with-not-found-end
  class Song
    module Activity
      class Update < Trailblazer::Activity::Railway
        step Model(Song, :find_by, not_found_terminus: true)
        step :validate
        step :save
        #~meths
        include T.def_steps(:validate, :save)
        #~meths end
      end
    end
  end
  #:update-with-not-found-end end

  it do
    assert_invoke Song::Activity::Update, params: {id: 1},
      seq: "[:validate, :save]", expected_ctx_variables: {model: Song.find_by(id: 1)}
    assert_invoke Song::Activity::Update, params: {id: nil}, terminus: :not_found

    #:not_found
    signal, (ctx, _) = Trailblazer::Activity::TaskWrap.invoke(Song::Activity::Update, [{params: {id: nil}},{}])
    puts signal #=> #<Trailblazer::Activity::End semantic=:not_found>
    #:not_found end
  end
end
