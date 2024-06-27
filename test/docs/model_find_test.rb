require "test_helper"

# step Model::Find(Song, find_method: :find_by, column_key: :id, params_key: :id)
# step Model::Find(Song, query: ->(ctx, params:, **) { where(id: params[:id_list]) })
# # syntax sugaring
# step Model::Find(Song, find_by: :id)
# step Model::Find(Song, :find)
# step Model::Find(query: ->(ctx, params:, **) { Song.where(id: params[:id_list]) })

class DocsModelFindTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find_by(id:)
      return if id.nil?
      new(id)
    end
  end
end

# Explicit options
#
# step Model::Find(Song, find_method: :find_method)
#
class Unit_ExplicitOptionsTest < Minitest::Spec
  Song = Class.new(DocsModelFindTest::Song) do
    def self.find_method(id:)
      return if id.nil?
      new(id)
    end
  end

  #:find_method
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      # explicit style:
      step Model::Find(Song, find_method: :find_method) # if it's _really_ Song.find_method(...)

      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:find_method end

  #~ctx_to_result
  it do
    #:find_method-invoke
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: "1"}, seq: [])
    ctx[:model] #=> #<struct Song id=1>
    #:find_method-invoke end

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id="1">}
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {short_id: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
  #~ctx_to_result end
end

# NOTE: unit test
#
# step Model::Find(Song, find_method: :find_by, column_key: :slug, params_key: :params_slug)
#
class ExplicitColumnKeyAndParamsKeyTest < Minitest::Spec
  Song = Class.new(DocsModelFindTest::Song) do
    def self.find_by(slug:)
      return if slug.nil?
      new(slug)
    end
  end

  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      # explicit style:
      step Model::Find(Song, find_method: :find_by, column_key: :slug, params_key: :params_slug)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end

  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {params_slug: "1"}, seq: [])
    ctx[:model] #=> #<struct Song id=1>

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id="1">}
  end

  it "fails" do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {params_slug: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
end

#
# step Model::Find(Song, query: ...)
#
class FindByQueryTest < Minitest::Spec
  Song = Class.new(DocsModelFindTest::Song) do
    def self.where(id:, user:)
      return [] if id.nil?
      [new([id, user])]
    end
  end

  #:query
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(
        Song,
        query: ->(ctx, id:, current_user:, **) { where(id: id, user: current_user).first }
      )
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end
  #:query end

  it do
    current_user = Module

    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: "1"}, current_user: current_user, seq: [])
    ctx[:model] #=> #<struct Song id=1>

    assert_equal ctx[:model].inspect, %(#<struct FindByQueryTest::Song id=[\"1\", Module]>)
  end

  it "fails" do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {id: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
end

#
# step Model::Find(Song, query: ..., params_key: :slug)
#
class FindByQueryWithParamsKeyTest < Minitest::Spec
  Song = Class.new(FindByQueryTest::Song)

  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song,
        query: ->(ctx, id:, current_user:, **) { where(id: id, user: current_user).first },
        params_key: :slug
      )
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end

  it do
    current_user = Module

    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {slug: "1"}, current_user: current_user, seq: [])
    ctx[:model] #=> #<struct Song id=1>

    assert_equal ctx[:model].inspect, %(#<struct FindByQueryWithParamsKeyTest::Song id=[\"1\", Module]>)
  end

  it "fails" do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {slug: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
end

#
# step Model::Find(Song, query: ..., ) do ... end
#
# FIXME: allow Model::Find() do ... end as well as { ... }
class FindByQueryWithParamsBlockTest < Minitest::Spec
  Song = Class.new(FindByQueryTest::Song)

  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, query: ->(ctx, id:, current_user:, **) { where(id: id, user: current_user).first }) { |ctx, params:, **|
        params[:slug_from_params]
      }
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end

  it do
    current_user = Module

    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {slug_from_params: "1"}, current_user: current_user, seq: [])
    ctx[:model] #=> #<struct Song id=1>

    assert_equal ctx[:model].inspect, %(#<struct FindByQueryWithParamsBlockTest::Song id=[\"1\", Module]>)
  end

  it "fails" do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {slug: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
end

# Shorthand
#
# step Model::Find(Song, find_by: :id)
#
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

# Shorthand
#
# step Model::Find(Song, find_by: :short_id)
#
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
      step Model::Find(Song, find_by: :short_id) # Song.find_by(short_id: params[:short_id])
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

# Shorthand with options
#
# step Model::Find(Song, find_by: :id, params_key: :slug)
#
class DocsModelFindByDifferentParamsKeyTest < Minitest::Spec
  Song = Class.new(DocsModelFindTest::Song)

  #:params_key
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, find_by: :id, params_key: :slug) # Song.find_by(id: params[:slug])
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

# Shorthand with different finder method
#
# step Model::Find(Song, find_with: :id)
#
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

# Shorthand with params_key block
#
# step Model::Find(Song, find_by: :id) { }
#
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

# Positional
#
# step Model::Find(Song, :find)
#
class DocsModelFindPositionaTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find(id)
      return if id.nil?
      new(id)
    end
  end

  #:find
  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, :find) # Song.find(id)
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

# Positional with params_key block
#
# step Model::Find(Song, :find) { ... }
#
class DocsModelFindPositionalWithParamsBlockTest < Minitest::Spec
  Song = Class.new(DocsModelFindPositionaTest::Song)

  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model::Find(Song, :find) { |ctx, params:, **| params[:params_slug] }
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end

  #~ctx_to_result
  it do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, {params: {params_slug: 1}, seq: []})
    ctx[:model] #=> #<struct Song id=1, title="Roxanne">

    assert_equal ctx[:model].inspect, %{#<struct #{Song} id=1>}
  end
  #~ctx_to_result end

  it "fails" do
    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Update, params: {params_slug: nil}, seq: [])
    assert_equal ctx[:model].inspect, %{nil}
  end
end

# Positional with #[]
#
# step Model::Find(Song, :[])
#
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
#
#
#
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
#
#
#
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

# Explicit terminus
#
# step Model::Find(Song, find_by: :id, not_found_terminus: true)
#
class ModelFind404TerminusTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find_by(id:)
      return if id.nil?
      return if id == 2
      new(id)
    end
  end

  #:not-found
  class Song
    module Activity
      class Update < Trailblazer::Activity::Railway
        step Model::Find(Song, find_by: :id, not_found_terminus: true)
        step :validate
        step :save
        #~meths
        include T.def_steps(:validate, :save)
        #~meths end
      end
    end
  end
  #:not-found end

  it "terminates on {not_found} for missing ID in {params}" do
    assert_invoke Song::Activity::Update, params: {id: 1},
      seq: "[:validate, :save]", expected_ctx_variables: {model: Song.find_by(id: 1)}
    assert_invoke Song::Activity::Update, params: {id: nil}, terminus: :not_found

    # no {params} at all.
    assert_invoke Song::Activity::Update, terminus: :not_found

    # no model matching ID.
    # NOTE: we assign {model: nil} - do we want that?
    assert_invoke Song::Activity::Update, params: {id: 2}, terminus: :not_found, expected_ctx_variables: {model: nil}

    #:not-found-invoke
    signal, (ctx, _) = Trailblazer::Activity::TaskWrap.invoke(Song::Activity::Update, [{params: {id: nil}},{}])
    puts signal #=> #<Trailblazer::Activity::End semantic=:not_found>
    #:not-found-invoke end
  end
end
