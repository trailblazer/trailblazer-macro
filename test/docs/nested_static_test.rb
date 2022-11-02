require "test_helper"

class DocsNestedStaticTest < Minitest::Spec


#@ {:auto_wire} without any other options
  module A
    class Song
    end

    #:id3
    module Song::Activity
      class Id3Tag < Trailblazer::Activity::Railway
        step :parse
        step :encode_id3
        #~meths
        include T.def_steps(:parse, :encode_id3)

        # def parse(ctx, seq:, **)
        #   ctx[:seq] = seq + [:parse]
        # end
        #~meths end
      end
    end
    #:id3 end

    module Song::Activity
      class VorbisComment < Trailblazer::Activity::Railway
        step :prepare_metadata
        step :encode_cover
        #~meths
        include T.def_steps(:prepare_metadata, :encode_cover)
        #~meths end
      end
    end

    #:create
    module Song::Activity
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
    #:create end

  end # A

  it "wires all nested termini to the outer tracks" do
    #@ success for Id3Tag
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :parse, :encode_id3, :save]}, params: {type: "mp3"}
    #@ failure for Id3Tag
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :parse]}, params: {type: "mp3"}, parse: false, terminus: :failure

    #@ success for VorbisComment
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover, :save]}, params: {type: "vorbis"}
    #@ failure for VorbisComment
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover]}, params: {type: "vorbis"}, encode_cover: false, terminus: :failure
  end

  it "is compatible with Debugging API" do
    trace = %{
#:create-trace
Song::Activity::Create
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
`-- End.success
#:create-trace end
}

    output, _ = trace A::Song::Activity::Create, params: {type: "vorbis"}, seq: []
    assert_equal output, trace.split("\n")[2..-2].join("\n").sub("Song::Activity::Create", "TOP")

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
    assert_equal Trailblazer::Developer::Introspect.find_path(A::Song::Activity::Create,
      ["Nested(decide_file_type)", DocsNestedStaticTest::A::Song::Activity::Id3Tag, :encode_id3])[0].task.inspect,
      %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=encode_id3>}

    Song = A::Song
    output =
    #:create-introspect
    Trailblazer::Developer.render(Song::Activity::Create,
      path: [
        "Nested(decide_file_type)", # ID of Nested()
        Song::Activity::Id3Tag      # ID of the nested {Id3Tag} activity.
      ]
    )
    #:create-introspect end
    assert_match /user_proc=encode_id3>/, output
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
          # TODO: also test returning false.
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

    #:unsupported-terminus
    module Song::Activity
      class VorbisComment < Trailblazer::Activity::Railway
        step :prepare_metadata
        step :encode_cover, Output(:failure) => End(:unsupported_file_format)
        #~meths
        include T.def_steps(:prepare_metadata, :encode_cover)
        #~meths end
      end
    end
    #:unsupported-terminus end

    module Song::Activity
      Id3Tag = B::Song::Activity::Id3Tag

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

  module D
    class Song; end

    module Song::Activity
      Id3Tag = A::Song::Activity::Id3Tag
      VorbisComment = C::Song::Activity::VorbisComment
    end

    #:create-output
    module Song::Activity
      class Create < Trailblazer::Activity::Railway
        step :model
        step Nested(
            :decide_file_type,
            auto_wire: [Id3Tag, VorbisComment]
          ),
          # Output and friends are used *after* Nested().
          # Connect VorbisComment's {unsupported_file_format} to our {failure} track:
          Output(:unsupported_file_format) => Track(:failure)

        step :save
        #~meths
        include T.def_steps(:model, :save)

        def decide_file_type(ctx, params:, **)
          params[:type] == "mp3" ? Id3Tag : VorbisComment
        end
        #~meths end
      end
    end
    #:create-output end
  end

  it "Id3Tag's invalid_metadata goes to {End.failure}" do
    assert_invoke D::Song::Activity::Create, seq: %{[:model, :prepare_metadata]}, params: {type: "vorbis"}, terminus: :failure, prepare_metadata: false
  end

  # TODO: return signal from Nested().

  #@ unit test
  module ComputeNested
    module_function

    def compute_nested(ctx, what:, **)
      what
    end
  end

  def activity_with_visible_variable
    Class.new(Trailblazer::Activity::Railway) do
      step ->(ctx, **) { ctx[:visible] = ctx.keys }
    end
  end

  def decider_with_visible_variable(ctx, what:, **)
    ctx[:visible_in_decider] << ctx.keys # this is horrible, we're bleeding through to a "global" variable.
    what
  end

  it "nested activity can see everything Nested() can see" do
    sub_activity = activity_with_visible_variable()

    #@ nested can see everything.
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(ComputeNested.method(:compute_nested),
      auto_wire: [sub_activity])

    assert_invoke activity, what: sub_activity, dont_look_at_me: true, expected_ctx_variables: {visible: [:seq, :what, :dont_look_at_me]}


    #@ nested can only see {:what}.
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(ComputeNested.method(:compute_nested),
      auto_wire: [sub_activity]),
      Trailblazer::Activity::Railway.In() => [:what]

    assert_invoke activity, what: sub_activity, dont_look_at_me: true, expected_ctx_variables: {visible: [:what]}
  end

# TODO: generic
  it "decider's variables are discarded" do
    sub_activity    = activity_with_visible_variable()
    compute_nested  = ->(ctx, what:, **) do
      ctx[:please_discard_me] = true
      what
    end

  #@ for Static
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(compute_nested,
      auto_wire: [sub_activity])

    #@ nested_activity and top activity cannot see things from decider.
    assert_invoke activity, what: sub_activity, expected_ctx_variables: {visible: [:seq, :what]}

  #@ for dynamic
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(compute_nested)

    #@ nested_activity and top activity cannot see things from decider.
    assert_invoke activity, what: sub_activity, expected_ctx_variables: {visible: [:seq, :what]}
  end

# TODO: generic
  it "without In/Out, decider and nested_activity see the same" do
    sub_activity    = activity_with_visible_variable()
    compute_nested  = method(:decider_with_visible_variable)

  #@ for Static
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(compute_nested,
      auto_wire: [sub_activity])

    #@ nested_activity and top activity cannot see things from decider.
    options = {
      what: sub_activity, expected_ctx_variables: {
        visible:            [:seq, :what, :visible_in_decider],
        visible_in_decider: [[:seq, :what, :visible_in_decider]]
      }
    }

    assert_invoke activity, **options, visible_in_decider: []

  #@ for dynamic
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(compute_nested)

    #@ nested_activity and top activity cannot see things from decider.
    assert_invoke activity, **options, visible_in_decider: []
  end

# TODO: generic
  it "with In/Out, decider and nested_activity see the same" do
    sub_activity    = activity_with_visible_variable()
    compute_nested  = method(:decider_with_visible_variable)
    in_out_options  = {
      Trailblazer::Activity::Railway.In() => {:activity_to_nest => :what},
      Trailblazer::Activity::Railway.In() => [:visible_in_decider]
    }

  #@ for Static
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(compute_nested,
      auto_wire: [sub_activity]).merge(in_out_options)

    #@ nested_activity and top activity cannot see things from decider.
    options = {
      please_discard_me: true,
      activity_to_nest: sub_activity, # renamed to {:what}
      expected_ctx_variables: {
        visible:            [:what, :visible_in_decider],
        visible_in_decider: [[:what, :visible_in_decider]]
      }
    }

    assert_invoke activity, **options, visible_in_decider: []

  #@ for dynamic
    activity = Class.new(Trailblazer::Activity::Railway)
    activity.step Trailblazer::Activity::Railway.Nested(compute_nested).
      merge(in_out_options)

    #@ nested_activity and top activity cannot see things from decider.
    assert_invoke activity, **options, visible_in_decider: []
  end
end

# TODO: test with :input/:output, tracing
# TODO: insntacemetho, callable etc
# =end

class DocsNestedDynamicTest < Minitest::Spec
  #@ dynamic without any other options
  module A
    class Song
    end

    module Song::Activity
      Id3Tag = DocsNestedStaticTest::A::Song::Activity::Id3Tag
      VorbisComment = DocsNestedStaticTest::A::Song::Activity::VorbisComment
    end

    #:dynamic
    module Song::Activity
      class Create < Trailblazer::Activity::Railway
        step :model
        step Nested(:decide_file_type) # Run either {Id3Tag} or {VorbisComment}
        step :save
        #~meths
        include T.def_steps(:model, :save)
        #~meths end
        def decide_file_type(ctx, params:, **)
          params[:type] == "mp3" ? Id3Tag : VorbisComment
        end
      end
    end
    #:dynamic end
  end # A

  it "wires all nested termini to the outer tracks" do
    #@ success for Id3Tag means success track on the  outside
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :parse, :encode_id3, :save]}, params: {type: "mp3"}
  end

  it "works with Tracing APi" do
    output, _ = trace A::Song::Activity::Create, params: {type: "mp3"}, seq: []

    assert_equal output, %{TOP
|-- Start.default
|-- model
|-- Nested(decide_file_type)
|   |-- Start.default
|   |-- decide
|   |   |-- Start.default
|   |   |-- #<Trailblazer::Activity::TaskBuilder::Task user_proc=decide_file_type>
|   |   |-- decision_result_to_flow_options
|   |   `-- End.success
|   |-- call_dynamic_nested_activity
|   |   `-- DocsNestedStaticTest::A::Song::Activity::Id3Tag
|   |       |-- Start.default
|   |       |-- parse
|   |       |-- encode_id3
|   |       `-- End.success
|   `-- End.success
|-- save
`-- End.success}
  end
end

