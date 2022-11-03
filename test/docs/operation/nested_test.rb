require "test_helper"

class DocsOperationNestedTest < Minitest::Spec
  require "trailblazer/operation/testing"
  include Trailblazer::Operation::Testing::Assertions

#@ {:auto_wire} without any other options
  module A
    class Song
    end

    #:id3
    module Song::Operation
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

    module Song::Operation
      class VorbisComment < Trailblazer::Operation
        step :prepare_metadata
        step :encode_cover
        #~meths
        include T.def_steps(:prepare_metadata, :encode_cover)
        #~meths end
      end
    end

    #:create
    module Song::Operation
      class Create < Trailblazer::Operation
        step :model
        step Nested(:decide_file_type,
          auto_wire: [Id3Tag, VorbisComment]), id: :nesti # explicitely define possible nested activities.
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

    # node, activity, _ = Trailblazer::Developer::Introspect.find_path(Song::Operation::Create, [:nesti])
    # puts Trailblazer::Developer::Render::TaskWrap.render_for(activity, node)
  end # A


  it "wires all nested termini to the outer tracks" do
    #@ success for Id3Tag
    assert_call A::Song::Operation::Create,  seq: %{[:model, :parse, :encode_id3, :save]}, params: {type: "mp3"}
    # assert_call AA::Song::Operation::Create, seq: %{[:model, :parse, :encode_id3, :save]}, params: {type: "mp3"}

    #@ failure for Id3Tag
    assert_call A::Song::Operation::Create,  seq: %{[:model, :parse]}, params: {type: "mp3"}, parse: false, terminus: :failure
    # assert_call AA::Song::Operation::Create, seq: %{[:model, :parse]}, params: {type: "mp3"}, parse: false, terminus: :failure

    #@ success for VorbisComment
    assert_call A::Song::Operation::Create,  seq: %{[:model, :prepare_metadata, :encode_cover, :save]}, params: {type: "vorbis"}
    # assert_call AA::Song::Operation::Create, seq: %{[:model, :prepare_metadata, :encode_cover, :save]}, params: {type: "vorbis"}
    #@ failure for VorbisComment
    assert_call A::Song::Operation::Create,  seq: %{[:model, :prepare_metadata, :encode_cover]}, params: {type: "vorbis"}, encode_cover: false, terminus: :failure
    # assert_call AA::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover]}, params: {type: "vorbis"}, encode_cover: false, terminus: :failure
  end

  it "is compatible with Debugging API" do
    trace = %{
#:create-trace
Song::Activity::Create
|-- Start.default
|-- model
|-- Nested(decide_file_type)
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
  end
end
