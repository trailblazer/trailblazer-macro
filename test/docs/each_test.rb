require "test_helper"


# step Macro::Each(:report_templates, key: :report_template) {
#   step Subprocess(ReportTemplate::Update), input: :input_report_template
#   fail :set_report_template_errors
# }

# def report_templates(ctx, **)      ctx["result.contract.default"].report_templates
# end

class EachTest < Minitest::Spec
  class Composer < Struct.new(:full_name, :email)

  end

  module B
    class Song < Struct.new(:id, :title, :band, :composers)
      def self.find_by(id:)
        Song.new(id, nil, nil, [Composer.new("Fat Mike"), Composer.new("El Hefe")])
      end
    end

    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        step Each(dataset_from: :composers_for_each) {
          step :notify_composers
        }

        # circuit-step interface! "decider interface"
        def composers_for_each(ctx, model:, **)
          model.composers
        end

        def notify_composers(ctx, index:, item:, **)
          ctx[:value] = [index, item.full_name]
        end
        #~meths
        def model(ctx, params:, **)
          ctx[:model] = Song.find_by(id: params[:id])
        end
        #~meths end
      end
    end
  end # B

  it "allows a dataset compute in the hosting activity" do
  #@ {:dataset} is not part of the {ctx}.
    assert_invoke B::Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 1),
        collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      }
  end
end

class DocsEachUnitTest < Minitest::Spec
  def self.block
    -> (*){
      step :compute_item

      def compute_item(ctx, item:, index:, **)
        ctx[:value] = "#{item}-#{index.inspect}"
      end
    }
  end

  it "with Trace" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      include T.def_steps(:a, :b)

      step :a
      step Each(&DocsEachUnitTest.block), id: "Each/1"
      step :b
    end

    ctx = {seq: [], dataset: [3,2,1]}

    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(activity, [ctx, {}])

    assert_equal Trailblazer::Developer::Trace::Present.(stack,
      node_options: {stack.to_a[0] => {label: "<a-Each-b>"}}), %{<a-Each-b>
|-- Start.default
|-- a
|-- Each/1
|   |-- Start.default
|   |-- Each.iterate.block
|   |   |-- invoke_block_activity.0
|   |   |   |-- Start.default
|   |   |   |-- compute_item
|   |   |   `-- End.success
|   |   |-- invoke_block_activity.1
|   |   |   |-- Start.default
|   |   |   |-- compute_item
|   |   |   `-- End.success
|   |   `-- invoke_block_activity.2
|   |       |-- Start.default
|   |       |-- compute_item
|   |       `-- End.success
|   `-- End.success
|-- b
`-- End.success}

  #@ compile time
  #@ make sure we can find tasks/compile-time artifacts in Each by using their {compile_id}.
    assert_equal Trailblazer::Developer::Introspect.find_path(activity,
      ["Each/1", "Each.iterate.block", "invoke_block_activity", :compute_item])[0].task.inspect,
      %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=compute_item>}
    # puts Trailblazer::Developer::Render::TaskWrap.(activity, ["Each/1", "Each.iterate.block", "invoke_block_activity", :compute_item])

  # TODO: grab runtime ctx for iteration 134
  end

  it "Each::Circuit" do
    activity = Trailblazer::Macro.Each(&DocsEachUnitTest.block)[:task]

    ctx = {
      dataset: [1,2,3]
    }

    # signal, (_ctx, _) = Trailblazer::Activity::TaskWrap.invoke(activity, [ctx])
    signal, (_ctx, _) = Trailblazer::Developer.wtf?(activity, [ctx])
    assert_equal _ctx[:collected_from_each], ["1-0", "2-1", "3-2"]
  end


  it "accepts iterated {block}" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item

        def compute_item(ctx, item:, index:, **)
          ctx[:value] = "#{item}-#{index.inspect}"
        end
      }
    end

    Trailblazer::Developer.wtf?(activity, [{dataset: ["one", "two", "three"]}, {}])

    assert_invoke activity, dataset: ["one", "two", "three"], expected_ctx_variables: {collected_from_each: ["one-0", "two-1", "three-2"]}
  end

  it "can see the entire ctx" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() { # expects {:dataset}
        step :compute_item_with_current_user

        def compute_item_with_current_user(ctx, item:, index:, current_user:, **)
          ctx[:value] = "#{item}-#{index.inspect}-#{current_user}"
        end
      }
    end

    Trailblazer::Developer.wtf?(
      activity,
      [{
          dataset:      ["one", "two", "three"],
          current_user: Object,
        },
      {}]
    )
    assert_invoke activity, dataset: ["one", "two", "three"], current_user: Object, expected_ctx_variables: {collected_from_each: ["one-0-Object", "two-1-Object", "three-2-Object"]}
  end

  it "allows taskWrap in Each" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item, In() => {:current_user => :user}, In() => [:item, :index]

        def compute_item(ctx, item:, index:, user:, **)
          ctx[:value] = "#{item}-#{index.inspect}-#{user}"
        end
      }

    end

    assert_invoke activity, dataset: ["one", "two", "three"], current_user: "Yogi", expected_ctx_variables: {collected_from_each: ["one-0-Yogi", "two-1-Yogi", "three-2-Yogi"]}
  end

  it "accepts operation" do
    nested_activity = Class.new(Trailblazer::Activity::Railway) do
      step :compute_item

      def compute_item(ctx, item:, index:, **)
        ctx[:value] = "#{item}-#{index.inspect}"
      end
    end

    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each(nested_activity)  # expects {:dataset}
    end
    # Trailblazer::Developer.wtf?(activity, [{dataset: ["one", "two", "three"]}, {}])

    assert_invoke activity, dataset: ["one", "two", "three"], expected_ctx_variables: {collected_from_each: ["one-0", "two-1", "three-2"]}
  end

  # Album = Struct.new(:id, :title, :songs) do
  #   def self.find(id)
  #     RECORDS.fetch(id)
  #   end
  # end

  # Song = Struct.new(:id, :title, :parent) do
  #   def self.clone_from(original_song)
  #     return if original_song.id == 3

  #     Song.new(
  #       original_song.id + 100,
  #       "clone of song-#{original_song.id}",
  #       original_song
  #     )
  #   end
  # end

  # RECORDS = {
  #   1 => Album.new(1, "album-1", [Song.new(1, "song-1"), Song.new(2, "song-2")]),
  #   2 => Album.new(2, "album-2", [Song.new(3, "song-3"), Song.new(4, "song-4")]),
  #   3 => Album.new(3, "album-3")
  # }

  # #:op
  # class Album::Clone < Trailblazer::Operation
  #   step Model(Album, :find)
  #   step :clone_album
  #   step Each(:songs, key: :original_song) {
  #     step :clone_song
  #     # ...
  #   }, id: :clone_songs

  #   #~methods
  #   # {iterable} returns any object to be iterated on
  #   def songs(ctx, model:, **)
  #     model.songs
  #   end

  #   # {:clone} gets called for each element and receives the current
  #   # element in `ctx` mapped to the given `key`.
  #   def clone_song(ctx, original_song:, original_song_index:, cloned_album:, **)
  #     cloned_song = Song.clone_from(original_song)
  #     return unless cloned_song

  #     cloned_album.songs[original_song_index] = cloned_song
  #   end

  #   def clone_album(ctx, model:, **)
  #     ctx[:cloned_album] = Album.new(model.id + 100, "clone of #{model.title}", [])
  #   end
  #   #~methods end
  # end
  # #:op end

  # it do
  #   Trailblazer::Developer.railway(Album::Clone).must_match(
  #     /\[>model.build,>clone_album,>clone_songs\]/
  #   )

  #   clone = Class.new(Album::Clone) do
  #     #:proc-callable
  #     step Each( ->(ctx, model:, **) { model.songs }, key: :original_song ) {
  #       step :clone_song

  #       step ->(ctx, original_song:, original_song_index:, **) {
  #         original_song         # current song from the enumerator
  #         original_song_index   # current index
  #       }
  #       # ...
  #     #:proc-callable end
  #     }, id: :each_songs, replace: :clone_songs

  #     def clone_album(ctx, seq:, **)
  #       seq << :clone_album
  #     end

  #     def clone_song(ctx, seq:, original_song:, **)
  #       return if original_song.id == 3
  #       seq << :clone_song
  #     end
  #   end

  #   result = clone.(seq: [], params: { id: 1 })
  #   _(result[:seq]).must_equal [:clone_album, :clone_song, :clone_song]

  #   result = clone.(seq: [], params: { id: 2 })
  #   _(result[:seq]).must_equal [:clone_album]
  # end

  # it "loops through all elements successfully" do
  #   result = Album::Clone.(params: { id: 1 })
  #   _(result.success?).must_equal true

  #   _(result[:cloned_album].title).must_equal "clone of album-1"
  #   _(result[:cloned_album].songs).must_equal [
  #     Song.new(101, "clone of song-1", Song.new(1, "song-1")),
  #     Song.new(102, "clone of song-2", Song.new(2, "song-2"))
  #   ]
  # end

  # it "breaks the loop when any step within wrap returns failure" do
  #   result = Album::Clone.(params: { id: 2 })
  #   _(result.success?).must_equal false

  #   _(result[:cloned_album].title).must_equal "clone of album-2"
  #   _(result[:cloned_album].songs).must_equal []
  # end

  # it "raises an exception when enumerable isn't valid" do
  #   assert_raises(Trailblazer::Macro::Each::EnumerableNotGiven) do
  #     Album::Clone.(params: { id: 3 })
  #   end
  # end
end
