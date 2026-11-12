  require "test_helper"

# Use {ComputeNested.method(:compute_nested)}
# Use #trace
# Use #assert_run

class DocsNestedStaticTest < Minitest::Spec
#@ {:static} without any other options
  module A
    class Song
    end

    #:id3
    module Song::Activity
      class Id3Tag < Trailblazer::Operation
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
      class VorbisComment < Trailblazer::Operation
        step :prepare_metadata
        step :encode_cover
        #~meths
        include T.def_steps(:prepare_metadata, :encode_cover)
        #~meths end
      end
    end

    #:create
    module Song::Activity
      class Create < Trailblazer::Operation
        step :model
        step Nested(:decide_file_type,
          static: [Id3Tag, VorbisComment]) # explicitely define possible nested activities.
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

  #@ and the same with a decider callable
  module AA
    module Song
      module Activity
        Id3Tag        = A::Song::Activity::Id3Tag
        VorbisComment = A::Song::Activity::VorbisComment

        class Create < Trailblazer::Operation
          class MyDecider
            def self.call(ctx, params:, **)
              params[:type] == "mp3" ? Id3Tag : VorbisComment
            end
          end

          step :model
          step Nested(MyDecider,
            static: [Id3Tag, VorbisComment]) # explicitely define possible nested activities.
          step :save
          #~meths
          include T.def_steps(:model, :save)
          #~meths end
        end
      end
    end
  end

  it "wires all nested termini to the outer tracks" do
    #@ success for Id3Tag
    assert_run A::Song::Activity::Create,  seq: [:model, :parse, :encode_id3, :save], target_ctx: {params: {type: "mp3"}, seq: []}, terminus: :success
    assert_run AA::Song::Activity::Create, seq: [:model, :parse, :encode_id3, :save], target_ctx: {params: {type: "mp3"}, seq: []}, terminus: :success

    #@ failure for Id3Tag
    assert_run A::Song::Activity::Create,  seq: [:model, :parse], target_ctx: {params: {type: "mp3"}, parse: false, seq: []}, terminus: :failure
    assert_run AA::Song::Activity::Create, seq: [:model, :parse], target_ctx: {params: {type: "mp3"}, parse: false, seq: []}, terminus: :failure

    #@ success for VorbisComment
    assert_run A::Song::Activity::Create,  seq: [:model, :prepare_metadata, :encode_cover, :save], target_ctx: {params: {type: "vorbis"}, seq: []}, terminus: :success
    assert_run AA::Song::Activity::Create, seq: [:model, :prepare_metadata, :encode_cover, :save], target_ctx: {params: {type: "vorbis"}, seq: []}, terminus: :success
    #@ failure for VorbisComment
    assert_run A::Song::Activity::Create,  seq: [:model, :prepare_metadata, :encode_cover], target_ctx: {params: {type: "vorbis"}, encode_cover: false, seq: []}, terminus: :failure
    assert_run AA::Song::Activity::Create, seq: [:model, :prepare_metadata, :encode_cover], target_ctx: {params: {type: "vorbis"}, encode_cover: false, seq: []}, terminus: :failure
  end

#@ Additional terminus {End.invalid_metadata} in Nested activity
  module B
    class Song
    end

    module Song::Activity
      class Id3Tag < Trailblazer::Operation
        InvalidMetadata = Class.new(Trailblazer::Activity::Signal)

        step :parse, Output(:invalid_metadata, signal: InvalidMetadata) => Terminus(:invalid_metadata) # We have a new terminus {End.invalid_metadata}
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

      class Create < Trailblazer::Operation
        step :model
        step Nested(:decide_file_type,
          static: [Id3Tag, VorbisComment]), # explicitely define possible nested activities.
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
      class VorbisComment < Trailblazer::Operation
        step :prepare_metadata
        step :encode_cover, Output(:failure) => Terminus(:unsupported_file_format)
        #~meths
        include T.def_steps(:prepare_metadata, :encode_cover)
        #~meths end
      end
    end
    #:unsupported-terminus end

    module Song::Activity
      Id3Tag = B::Song::Activity::Id3Tag

      class Create < Trailblazer::Operation
        step :model
        step Nested(:decide_file_type,
          static: [Id3Tag, VorbisComment]), # explicitely define possible nested activities.
          Output(:invalid_metadata) => Track(:failure),
          Output(:unsupported_file_format) => Terminus(:internal_error)

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
      class Create < Trailblazer::Operation
        step :model
        step Nested(
            :decide_file_type,
            static: [Id3Tag, VorbisComment]
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


  #@ FastTrack is mapped to outer FastTrack.
  module E
    class Song
    end

    module Song::Activity
      class Id3Tag < Trailblazer::Activity::FastTrack
        step :parse,
          fail_fast: true,
          pass_fast: true
        step :encode_id3
        include T.def_steps(:parse, :encode_id3)
      end

      VorbisComment = DocsNestedStaticTest::C::Song::Activity::VorbisComment # has an {End.unsupported_file_format} terminus.
    end

    #:static-fasttrack
    module Song::Activity
      class Create < Trailblazer::Activity::FastTrack
        step :model
        step Nested(:decide_file_type, static: [Id3Tag, VorbisComment]),
          fast_track: true,
          Output(:unsupported_file_format) => Terminus(:unsupported_file_format)
        step :save
        #~meths
        include T.def_steps(:model, :save)
        def decide_file_type(ctx, params:, **)
          params[:type] == "mp3" ? Id3Tag : VorbisComment
        end
        #~meths end
      end
    end
    #:static-fasttrack end
    # puts Trailblazer::Developer.render(Song::Activity::Create)
  end # C

  it "FastTrack from nested_activity are mapped to respective tracks" do
    #@ {End.pass_fast} goes success for Id3Tag
    assert_invoke E::Song::Activity::Create, seq: %{[:model, :parse]}, params: {type: "mp3"}, terminus: :pass_fast
    #@ {End.fail_fast} goes failure for Id3Tag
    assert_invoke E::Song::Activity::Create, seq: %{[:model, :parse]}, params: {type: "mp3"}, parse: false, terminus: :fail_fast

    assert_invoke E::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover, :save]}, params: {type: "vorbis"}
    assert_invoke E::Song::Activity::Create, seq: %{[:model, :prepare_metadata]}, params: {type: "vorbis"}, prepare_metadata: false, terminus: :failure
    #@ VorbisComment :unsupported_file_format is mapped to :failure
    assert_invoke E::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover]}, params: {type: "vorbis"}, encode_cover: false, terminus: :unsupported_file_format
  end
end

class NestedStrategyComplianceTest < Minitest::Spec
  Song = DocsNestedStaticTest::A::Song

  it "is compatible with Debugging API" do
    trace = %{
#:create-trace
Song::Activity::Create
|-- Start.default
|-- model
|-- Nested/decide_file_type
|   |-- Start.default
|   |-- route_to_nested_activity
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

Trailblazer::Developer.wtf?(Song::Activity::Create, {params: {type: "vorbis"}, seq: []})

    output, _ = trace Song::Activity::Create, params: {type: "vorbis"}, seq: []

    assert_equal output, trace.split("\n")[2..-2].join("\n").sub("Song::Activity::Create", "TOP")

    output, _ = trace Song::Activity::Create, params: {type: "mp3"}, seq: []

    assert_equal output, %{TOP
|-- Start.default
|-- model
|-- Nested/decide_file_type
|   |-- Start.default
|   |-- route_to_nested_activity
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
    assert_equal CU.strip(Trailblazer::Developer::Introspect.find_path(Song::Activity::Create,
      ["Nested/decide_file_type", DocsNestedStaticTest::A::Song::Activity::Id3Tag, :encode_id3])[0].task.inspect),
      %(#<Trailblazer::Activity::Circuit::Step::Binary:0x @step=#<Trailblazer::Activity::Circuit::Step::Option:0x @step=#<Trailblazer::Activity::Option::InstanceMethod:0x @filter=:encode_id3>>>)

    output =
    #:create-introspect
    Trailblazer::Developer.render(Song::Activity::Create,
      path: [
        "Nested/decide_file_type", # ID of Nested()
        Song::Activity::Id3Tag      # ID of the nested {Id3Tag} activity.
      ]
    )
    #:create-introspect end
    assert_match /@filter=:encode_id3>/, output
  end

  # TODO: test more options.
  it "assigns ID via {Macro.id_for}" do
    activity = Class.new(Trailblazer::Operation) do
      step Nested(:decide_file_type, static: [Trailblazer::Operation])
    end

    assert_equal Trailblazer::Developer::Introspect.find_path(activity,
      ["Nested/decide_file_type"])[0].id, %{Nested/decide_file_type}
  end

  it do
    skip

    #:patch
    faster_mp3 = Trailblazer::Activity::DSL::Linear.Patch(
      Song::Activity::Create,
      ["Nested/decide_file_type", Song::Activity::Id3Tag] => -> { step :fast_encode_id3, replace: :encode_id3 }
    )
    #:patch end
    faster_mp3.include(T.def_steps(:fast_encode_id3))
# Trailblazer::Developer.wtf?(faster_mp3, [{params: {type: "mp3"}, seq: []}])

  #@ Original class isn't changed.
    assert_invoke Song::Activity::Create, params: {type: "mp3"}, seq: "[:model, :parse, :encode_id3, :save]"
  #@ Patched class runs
    assert_invoke faster_mp3, params: {type: "mp3"}, seq: "[:model, :parse, :fast_encode_id3, :save]"
  end
end
