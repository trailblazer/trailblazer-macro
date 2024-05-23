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
  module Song::Activity
    class Create < Trailblazer::Activity::Railway
      step Model(Song, :new)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:op end

  #:update
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model(Song, :find_by)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:update end

  it "defaults {:params} to empty hash when not passed" do
    assert_invoke Song::Activity::Create, seq: "[:validate, :save]",
      expected_ctx_variables: {model: Song.new}

    assert_invoke Song::Activity::Update, seq: "[]",
      terminus: :failure
  end

  #~ctx_to_result
  it do
    #:create
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create, params: {}, seq: [])
    puts ctx[:model] #=> #<struct Song id=nil, title=nil>
    #:create end

    assert_invoke Song::Activity::Create, params: {},
      seq: "[:validate, :save]", expected_ctx_variables: {model: Song.new}
  end

  it do
    #:update-ok
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: 1}, seq: [])
    ctx[:model] #=> #<Song id=1, ...>
    puts signal #=> #<Trailblazer::Activity::End semantic=:success>
    #:update-ok end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=1, title=nil>}
    assert_equal signal.to_h[:semantic], :success
  end

  it do
    #:update-fail
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {})
    ctx[:model] #=> nil
    puts signal #=> #<Trailblazer::Activity::End semantic=:failure>
    #:update-fail end

    assert_equal ctx[:model].inspect, %{nil}
    assert_equal signal.to_h[:semantic], :failure
  end
  #~ctx_to_result end
end

class DocsModelFindByTitleTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)

  #:update-with-find-by-key
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model(Song, :find_by, :title) # third positional argument.
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:update-with-find-by-key end

  #~ctx_to_result
  it do
    #:update-with-find-by-key-ok
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {title: "Test"}, seq: [])
    ctx[:model] #=> #<struct Song id=2, title="Test">
    #:update-with-find-by-key-ok end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=2, title="Test">}
  end

  it do
    #:key-title-fail
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {title: nil}, seq: [])

    assert_equal ctx[:model].inspect, %{nil}
    #:key-title-fail end
  end
  #~ctx_to_result end
end

class DocsModelAccessorTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)

  #:show
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model(Song, :[])
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:show end

  #~ctx_to_result
  it do
    #:show-ok
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: 1}, seq: [])
    ctx[:model] #=> #<struct Song id=1, title="Roxanne">
    #:show-ok end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=100, title=nil>}
  end
  #~ctx_to_result end
end

class DocsModelDependencyInjectionTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)

  module Song::Activity
    class Create < Trailblazer::Activity::Railway
      step Model(Song, :new)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end

  it "allows injecting {:model.class} and friends" do
    class Hit < Song
    end

    #:di-model-class
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create, params: {}, :"model.class" => Hit, seq: [])
    #:di-model-class end

    assert_equal ctx[:model].inspect, %{#<struct #{Hit} id=nil, title=nil>}

  # inject all variables
    #:di-all
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create,
      params:               {title: "Olympia"}, # some random variable.
      "model.class":        Hit,
      "model.action":       :find_by,
      "model.find_by_key":  :title, seq: []
    )
    #:di-all end

    assert_equal ctx[:model].inspect, %{#<struct #{Hit} id=2, title="Olympia">}
end

  # use empty Model() and inject {model.class} and {model.action}
class DocsModelEmptyDITest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)
  Hit  = Class.new(Song)

  #:op-model-empty
  module Song::Activity
    class Create < Trailblazer::Activity::Railway
      step Model()
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
    #:op-model-empty end
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create, params: {}, :"model.class" => Hit, seq: [])

    assert_equal ctx[:model].inspect, %{#<struct #{Hit} id=nil, title=nil>}
  end
end

class DocsModelIOTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)
  Hit  = Class.new(Song)

  it "allows to use composable I/O with macros" do
    #:in
    module Song::Activity
      class Create < Trailblazer::Operation
        step Model(Song, :find_by),
          In() => ->(ctx, my_id:, **) { ctx.merge(params: {id: my_id}) } # Model() needs {params[:id]}.
        # ...
      end
    end
    #:in end

    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create, params: {}, my_id: 1, :"model.class" => Hit)

    assert_equal ctx[:model].inspect, %{#<struct #{Hit} id=1, title=nil>}
=begin
#:in-call
result = Create.(my_id: 1)
#:in-call end
=end
    end
  end
end

class Model404TerminusTest < Minitest::Spec
  Song = Class.new(DocsModelTest::Song)
  #:update-with-not-found-end
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model(Song, :find_by, not_found_terminus: true)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:update-with-not-found-end end

  it do
    assert_invoke Song::Activity::Update, params: {id: 1},
      seq: "[:validate, :save]", expected_ctx_variables: {model: Song.find_by(id: 1)}
    assert_invoke Song::Activity::Update, params: {id: nil}, terminus: :not_found

    #:not_found
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: nil})
    puts signal #=> #<Trailblazer::Activity::End semantic=:not_found>
    #:not_found end
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
