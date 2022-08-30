require "test_helper"

class DocsEachTest < Minitest::Spec
  it "what" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item

        def compute_item(ctx, item:, index:, **)
          ctx[:value] = "#{item}-#{index.inspect}"
        end
      }

    end

    assert_invoke activity, dataset: ["one", "two", "three"], expected_ctx_variables: {collected_from_each: ["one-0", "two-1", "three-2"]}
  end

  it "allows taskWrap in Each" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item, In() => {:current_user => :user}, In() => [:item, :index]
      }

      def compute_item(ctx, item:, index:, user:, **)
        ctx[:value] = "#{item}-#{index.inspect}-#{user}"
      end
    end

    assert_invoke activity, dataset: ["one", "two", "three"], current_user: "Yogi", expected_ctx_variables: {collected_from_each: ["one-0-Yogi", "two-1-Yogi", "three-2-Yogi"]}
  end



  Album = Struct.new(:id, :title, :songs) do
    def self.find(id)
      RECORDS.fetch(id)
    end
  end

  Song = Struct.new(:id, :title, :parent) do
    def self.clone_from(original_song)
      return if original_song.id == 3

      Song.new(
        original_song.id + 100,
        "clone of song-#{original_song.id}",
        original_song
      )
    end
  end

  RECORDS = {
    1 => Album.new(1, "album-1", [Song.new(1, "song-1"), Song.new(2, "song-2")]),
    2 => Album.new(2, "album-2", [Song.new(3, "song-3"), Song.new(4, "song-4")]),
    3 => Album.new(3, "album-3")
  }

  #:op
  class Album::Clone < Trailblazer::Operation
    step Model(Album, :find)
    step :clone_album
    step Each(:songs, key: :original_song) {
      step :clone_song
      # ...
    }, id: :clone_songs

    #~methods
    # {iterable} returns any object to be iterated on
    def songs(ctx, model:, **)
      model.songs
    end

    # {:clone} gets called for each element and receives the current
    # element in `ctx` mapped to the given `key`.
    def clone_song(ctx, original_song:, original_song_index:, cloned_album:, **)
      cloned_song = Song.clone_from(original_song)
      return unless cloned_song

      cloned_album.songs[original_song_index] = cloned_song
    end

    def clone_album(ctx, model:, **)
      ctx[:cloned_album] = Album.new(model.id + 100, "clone of #{model.title}", [])
    end
    #~methods end
  end
  #:op end

  it do
    Trailblazer::Developer.railway(Album::Clone).must_match(
      /\[>model.build,>clone_album,>clone_songs\]/
    )

    clone = Class.new(Album::Clone) do
      #:proc-callable
      step Each( ->(ctx, model:, **) { model.songs }, key: :original_song ) {
        step :clone_song

        step ->(ctx, original_song:, original_song_index:, **) {
          original_song         # current song from the enumerator
          original_song_index   # current index
        }
        # ...
      #:proc-callable end
      }, id: :each_songs, replace: :clone_songs

      def clone_album(ctx, seq:, **)
        seq << :clone_album
      end

      def clone_song(ctx, seq:, original_song:, **)
        return if original_song.id == 3
        seq << :clone_song
      end
    end

    result = clone.(seq: [], params: { id: 1 })
    _(result[:seq]).must_equal [:clone_album, :clone_song, :clone_song]

    result = clone.(seq: [], params: { id: 2 })
    _(result[:seq]).must_equal [:clone_album]
  end

  it "loops through all elements successfully" do
    result = Album::Clone.(params: { id: 1 })
    _(result.success?).must_equal true

    _(result[:cloned_album].title).must_equal "clone of album-1"
    _(result[:cloned_album].songs).must_equal [
      Song.new(101, "clone of song-1", Song.new(1, "song-1")),
      Song.new(102, "clone of song-2", Song.new(2, "song-2"))
    ]
  end

  it "breaks the loop when any step within wrap returns failure" do
    result = Album::Clone.(params: { id: 2 })
    _(result.success?).must_equal false

    _(result[:cloned_album].title).must_equal "clone of album-2"
    _(result[:cloned_album].songs).must_equal []
  end

  it "raises an exception when enumerable isn't valid" do
    assert_raises(Trailblazer::Macro::Each::EnumerableNotGiven) do
      Album::Clone.(params: { id: 3 })
    end
  end
end
