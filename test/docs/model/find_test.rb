require "test_helper"

class DocsModelFindTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find_by(id:)
      return if id.nil?
      new(id)
    end
  end
end

# find_by: :id
class DocsModelFindByColumnTest < Minitest::Spec
  Song = Class.new(DocsModelFindTest::Song)

  #:find_by_id
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, find_by: :id)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:find_by_id end

  #~ctx_to_result
  it do
    #:find_by_id-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: "1"}, seq: [])
    ctx[:model] #=> #<struct Song id=1>
    #:find_by_id-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id="1">}
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {short_id: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
  #~ctx_to_result end

# TODO: put this test somewhere else
  it "doesn't leak anything but {:model} to the outer world" do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: "1"}, seq: [])

    assert_equal ctx.keys.inspect, %([:params, :seq, :model])
  end
end

# find_by: :short_id
class DocsModelFindByDifferentColumnTest < Minitest::Spec
  Song = Struct.new(:short_id) do
    def self.find_by(short_id:)
      return if short_id.nil?
      new(short_id)
    end
  end

  #:find_by_column
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, find_by: :short_id)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:find_by_column end

  #~ctx_to_result
  it do
    #:find_by_column-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {short_id: "1f396"}, seq: [])
    ctx[:model] #=> #<struct Song short_id="1f396">
    #:find_by_column-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} short_id="1f396">}
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {short_id: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
  #~ctx_to_result end
end

class DocsModelFindByColumnAndDifferentParamsKeyTest < Minitest::Spec
  Song = Class.new(DocsModelFindTest::Song)

  #:params_key
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, find_by: :id, params_key: :slug)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:params_key end

  #~ctx_to_result
  it do
    #:params_key-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {slug: "1f396"}, seq: [])
    ctx[:model] #=> #<struct Song id=2, id="1f396">
    #:params_key-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id="1f396">}
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {slug: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
  #~ctx_to_result end
end
