require "test_helper"

class DocsNestedStaticTest < Minitest::Spec
  DatabaseError = Class.new(Trailblazer::Activity::Signal)

  def trace(activity, ctx)
    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(activity, [ctx, {}])
    return Trailblazer::Developer::Trace::Present.(stack, node_options: {stack.to_a[0]=>{label: "TOP"}}).gsub(/:\d+/, ""), signal, ctx
  end

  module A
    class Song

    end

    module Song::Activity
      class Id3Tag < Trailblazer::Activity::Railway
        step :parse
        step :encode_id3
        #~meths
        include T.def_steps(:parse, :encode_id3)
        #~meths end
      end

      class VorbisComment < Trailblazer::Activity::Railway
        step :prepare_metadata
        step :encode_cover
        #~meths
        include T.def_steps(:prepare_metadata, :encode_cover)
        #~meths end
      end

      class Create < Trailblazer::Activity::Railway
        step :model
        step Nested(:decide_file_type,
          auto_wire: [Id3Tag, VorbisComment]) # explicitely define possible nested activities.

        step :save
        #~meths
        include T.def_steps(:model, :save)
        #~meths end

        def decide_file_type(ctx, params:, **)
          params[:type] == "mp3" ? Id3Tag : VorbisComment
        end
      end

    end
  end # A

  it "auto_wire: []" do
    #@ success for Id3Tag
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :parse, :encode_id3, :save]}, params: {type: "mp3"}
    #@ failure for Id3Tag
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :parse]}, params: {type: "mp3"}, parse: false, terminus: :failure

    #@ success for VorbisComment
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover, :save]}, params: {type: "vorbis"}
    #@ failure for VorbisComment
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover]}, params: {type: "vorbis"}, encode_cover: false, terminus: :failure


    output, _ = trace A::Song::Activity::Create, params: {type: "vorbis"}, seq: []
    assert_equal output, %{TOP
|-- Start.default
|-- model
|-- Nested(decide_file_type)
|   |-- Start.default
|   |-- decide
|   |   |-- Start.default
|   |   |-- #<Trailblazer::Activity::TaskBuilder::Task user_proc=decide_file_type>
|   |   |-- dispatch_to_terminus
|   |   `-- End.decision:DocsNestedStaticTest::A::Song::Activity::VorbisComment
|   |-- DocsNestedStaticTest::A::Song::Activity::VorbisComment
|   |   |-- Start.default
|   |   |-- prepare_metadata
|   |   |-- encode_cover
|   |   `-- End.success
|   `-- End.success
|-- save
`-- End.success}

    output, _ = trace A::Song::Activity::Create, params: {type: "mp3"}, seq: []
    assert_equal output, %{TOP
|-- Start.default
|-- model
|-- Nested(decide_file_type)
|   |-- Start.default
|   |-- decide
|   |   |-- Start.default
|   |   |-- #<Trailblazer::Activity::TaskBuilder::Task user_proc=decide_file_type>
|   |   |-- dispatch_to_terminus
|   |   `-- End.decision:DocsNestedStaticTest::A::Song::Activity::Id3Tag
|   |-- DocsNestedStaticTest::A::Song::Activity::Id3Tag
|   |   |-- Start.default
|   |   |-- parse
|   |   |-- encode_id3
|   |   `-- End.success
|   `-- End.success
|-- save
`-- End.success}


    #@ compile time
  #@ make sure we can find tasks/compile-time artifacts in Each by using their {compile_id}.
    # assert_equal Trailblazer::Developer::Introspect.find_path(activity,
    #   ["Each/1", "Each.iterate.block", "invoke_block_activity", :compute_item])[0].task.inspect,
    #   %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=compute_item>}
  end

#@ Additional terminus {End.invalid_metadata} in Nested activity
  module B
    class Song
    end

    module Song::Activity
      class Id3Tag < Trailblazer::Activity::Railway
        InvalidMetadata = Class.new(Trailblazer::Activity::Signal)

        step :parse, Output(InvalidMetadata, :invalid_metadata) => End(:invalid_metadata) # We have a new terminus {End.invalid_metadata}
        step :encode_id3
        #~meths
        include T.def_steps(:parse, :encode_id3)

        def validate_metadata(params)
          params[:is_valid]
        end
        #~meths end
        def parse(ctx, params:, **)
          unless validate_metadata(params)
            return InvalidMetadata
          end
          #~body
          ctx[:seq] << :parse
          true
          #~body end
        end
      end

      VorbisComment = A::Song::Activity::VorbisComment

      class Create < Trailblazer::Activity::Railway
        step :model
        step Nested(:decide_file_type,
          auto_wire: [Id3Tag, VorbisComment]), # explicitely define possible nested activities.
          Output(:invalid_metadata) => Track(:failure)

        step :save
        #~meths
        include T.def_steps(:model, :save)
        #~meths end

        def decide_file_type(ctx, params:, **)
          params[:type] == "mp3" ? Id3Tag : VorbisComment
        end
      end

    end
  end # B

# Add another End.ExeedsLimit to {VorbisComment}
  module C
    class Song
    end

    module Song::Activity
      Id3Tag = B::Song::Activity::Id3Tag

      class VorbisComment < Trailblazer::Activity::Railway
        step :prepare_metadata
        step :encode_cover, Output(:failure) => End(:unsupported_file_format)
        #~meths
        include T.def_steps(:prepare_metadata, :encode_cover)
        #~meths end
      end

      class Create < Trailblazer::Activity::Railway
        step :model
        step Nested(:decide_file_type,
          auto_wire: [Id3Tag, VorbisComment]), # explicitely define possible nested activities.
          Output(:invalid_metadata) => Track(:failure),
          Output(:unsupported_file_format) => End(:internal_error)

        step :save
        include T.def_steps(:model, :save)

        def decide_file_type(ctx, params:, **)
          params[:type] == "mp3" ? Id3Tag : VorbisComment
        end
      end

    end
  end

  it "handle {InvalidMetadata}" do
    #@ Id3Tag with valid metadata
    assert_invoke B::Song::Activity::Create, seq: %{[:model, :parse, :encode_id3, :save]}, params: {type: "mp3", is_valid: true}, terminus: :success

    #@ InvalidMetadata returned from Id3Tag#parse
    assert_invoke B::Song::Activity::Create, seq: %{[:model]}, params: {type: "mp3", is_valid: false}, terminus: :failure
  end

  it "handle {failure} from VorbisComment" do
    assert_invoke C::Song::Activity::Create, seq: %{[:model, :prepare_metadata]}, params: {type: "vorbis"}, terminus: :failure, prepare_metadata: false

    #@ UnsupportedFileFormat
    assert_invoke C::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover]}, params: {type: "vorbis"}, terminus: :internal_error, encode_cover: false
  end

  #@ unit test
  module ComputeNested
    module_function

    def compute_nested(ctx, what:, **)
      what
    end
  end

  it "nested activity can see everything Nested() can see" do
    sub_activity = Class.new(Trailblazer::Activity::Railway) do
      step ->(ctx, **) { ctx[:visible] = ctx.keys }
    end

    #@ nested can see everything.
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(ComputeNested.method(:compute_nested),
      auto_wire: [sub_activity])

    assert_invoke activity, what: sub_activity, dont_look_at_me: true, expected_ctx_variables: {visible: [:seq, :what, :dont_look_at_me]}


    #@ nested can only {:what}.
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(ComputeNested.method(:compute_nested),
      auto_wire: [sub_activity]),
      Trailblazer::Activity::Railway.In() => [:what]

    assert_invoke activity, what: sub_activity, dont_look_at_me: true, expected_ctx_variables: {visible: [:what]}
  end
end

# TODO: test with :input/:output, tracing
# =end
