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

class DocsModelFindWithTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find_with(id:)
      return if id.nil?
      new(id)
    end
  end

  #:find_with
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, find_with: :id)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:find_with end

  #~ctx_to_result
  it do
    #:find_with-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: 2}, seq: [])
    ctx[:model] #=> #<struct Song id=2>
    #:find_with-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=2>}
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
  #~ctx_to_result end
end

class DocsModelIdFromProcTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find_by(id:)
      return if id.nil?
      new(id)
    end
  end

  #:id_from
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, find_by: :id) { |ctx, params:, **|
        params[:song] && params[:song][:id]
      }
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:id_from end

  #~ctx_to_result
  it do
    #:id_from-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {song: {id: "1f396"}}, seq: [])
    ctx[:model] #=> #<struct Song id="1f396">
    #:id_from-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id="1f396">}
    assert_equal ctx[:seq].inspect, %([:validate, :save])
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {}, seq: [])

    assert_equal ctx[:model].inspect, %{nil}
    assert_equal ctx[:seq].inspect, %([])
  end
  #~ctx_to_result end
end

class DocsModelFindTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find(id)
      return if id.nil?
      new(id)
    end
  end

  #:find
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, :find)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:find end

  #~ctx_to_result
  it do
    #:find-ok
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, {params: {id: 1}, seq: []})
    ctx[:model] #=> #<struct Song id=1, title="Roxanne">
    #:find-ok end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=1>}
  end
  #~ctx_to_result end
end

class DocsModelAccessorTest < Minitest::Spec
  Song = Struct.new(:id, :title) do
    def self.[](id)
      id.nil? ? nil : new(id+99)
    end
  end

  #:show
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, :[])
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
    signal, (ctx, _) = Trailblazer::Developer.wtf?(Song::Activity::Update, [{params: {id: 1}, seq: []}])
    ctx[:model] #=> #<struct Song id=1, title="Roxanne">
    #:show-ok end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=100, title=nil>}
  end
  #~ctx_to_result end
end

# class DocsModelBlockTest < Minitest::Spec
#   Song = Class.new(DocsModelIdFromProcTest::Song)

#   #:block
#   module Song::Activity
#     class Update < Trailblazer::Activity::Railway
#       step Model() do |ctx, params:, **|

#       end
#       step :validate
#       step :save
#       #~meths
#       include T.def_steps(:validate, :save)
#       #~meths end
#     end
#   end
#   #:block end

#   #~ctx_to_result
#   it do
#     #:block-invoke
#     signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {song: {id: "1f396"}}, seq: [])
#     ctx[:model] #=> #<struct Song id="1f396">
#     #:block-invoke end

#     assert_equal ctx[:model].inspect, %{#<struct #{Song} id="1f396">}
#     assert_equal ctx[:seq].inspect, %([:validate, :save])
#   end

#   it do
#     signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {}, seq: [])

#     assert_equal ctx[:model].inspect, %{nil}
#     assert_equal ctx[:seq].inspect, %([])
#   end
#   #~ctx_to_result end
# end

# new
class DocsModelNewTest < Minitest::Spec
  Song = Class.new(DocsModelFindTest::Song)

  #:new
  module Song::Activity
    class Create < Trailblazer::Activity::Railway
      step Model::Build(Song, :new)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:new end

  #~ctx_to_result
  it do
    #:new-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create, params: {}, seq: [])
    ctx[:model] #=> #<struct Song id=1>
    #:new-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=nil>}
  end
  #~ctx_to_result end
end

# build
class DocsModelBuildTest < Minitest::Spec
  Song = Struct.new(:id)
  Song.singleton_class.alias_method :build, :new

  #:build
  module Song::Activity
    class Create < Trailblazer::Activity::Railway
      step Model::Build(Song, :build)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:build end

  #~ctx_to_result
  it do
    #:build-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Create, params: {}, seq: [])
    ctx[:model] #=> #<struct Song id=1>
    #:build-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=nil>}
  end
  #~ctx_to_result end
end
