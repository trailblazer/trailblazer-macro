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
    assert_run B::Song::Activity::Create, seq: [:model, :parse, :encode_id3, :save], target_ctx: {seq: [], params: {type: "mp3", is_valid: true}}, terminus: :success

    #@ InvalidMetadata returned from Id3Tag#parse
    assert_run B::Song::Activity::Create, seq: [:model], target_ctx: {seq: [], params: {type: "mp3", is_valid: false}}, terminus: :failure
  end

  it "handle {failure} from VorbisComment" do
    assert_run C::Song::Activity::Create, seq: [:model, :prepare_metadata], target_ctx: {seq: [], params: {type: "vorbis"}, prepare_metadata: false}, terminus: :failure

    #@ UnsupportedFileFormat
    assert_run C::Song::Activity::Create, seq: [:model, :prepare_metadata, :encode_cover], target_ctx: {seq: [], params: {type: "vorbis"}, encode_cover: false}, terminus: :internal_error
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
    assert_run D::Song::Activity::Create, seq: [:model, :prepare_metadata], target_ctx: {params: {type: "vorbis"}, prepare_metadata: false, seq: []}, terminus: :failure
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
    assert_run E::Song::Activity::Create, seq: [:model, :parse], target_ctx: {seq: [], params: {type: "mp3"}}, terminus: :pass_fast
    #@ {End.fail_fast} goes failure for Id3Tag
    assert_run E::Song::Activity::Create, seq: [:model, :parse], target_ctx: {seq: [], params: {type: "mp3"}, parse: false}, terminus: :fail_fast

    assert_run E::Song::Activity::Create, seq: [:model, :prepare_metadata, :encode_cover, :save], target_ctx: {seq: [], params: {type: "vorbis"}}, terminus: :success
    assert_run E::Song::Activity::Create, seq: [:model, :prepare_metadata], target_ctx: {seq: [], params: {type: "vorbis"}, prepare_metadata: false}, terminus: :failure
    #@ VorbisComment :unsupported_file_format is mapped to :failure
    assert_run E::Song::Activity::Create, seq: [:model, :prepare_metadata, :encode_cover], target_ctx: {seq: [], params: {type: "vorbis"}, encode_cover: false}, terminus: :unsupported_file_format
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
    pp Song::Activity::Create.config.circuit.nodes[:"Nested/decide_file_type"].task.nodes[:"task_wrap.call_task"].task
      .nodes[:"DocsNestedStaticTest::A::Song::Activity::Id3Tag"].task.config.circuit

    #:patch
    faster_mp3 = Trailblazer::Circuit::Node::Patch.(
      Song::Activity::Create,
      ["Nested/decide_file_type", Song::Activity::Id3Tag],
      adds: [

        -> { step :fast_encode_id3, replace: :encode_id3 }
      ]
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
      class Create < Trailblazer::Operation
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

  #@ and the same with a decider callable
  module AA
    module Song
      module Activity
        Id3Tag        = A::Song::Activity::Id3Tag
        VorbisComment = A::Song::Activity::VorbisComment

        class Create < Trailblazer::Operation
          MyDecider = DocsNestedStaticTest::AA::Song::Activity::Create::MyDecider

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

  it "nested {success} and {failure} are wired to respective tracks on the outside" do
    #@ success for Id3Tag means success track on the  outside
    assert_run A::Song::Activity::Create,  seq: [:model, :parse, :encode_id3, :save], target_ctx: {params: {type: "mp3"}, seq: []}, terminus: :success
    assert_run AA::Song::Activity::Create, seq: [:model, :parse, :encode_id3, :save], target_ctx: {params: {type: "mp3"}, seq: []}, terminus: :success
    assert_run A::Song::Activity::Create,  seq: [:model, :parse, :encode_id3], terminus: :failure, target_ctx: {params: {type: "mp3"}, seq: [], encode_id3: false}
    assert_run AA::Song::Activity::Create, seq: [:model, :parse, :encode_id3], terminus: :failure, target_ctx: {params: {type: "mp3"}, seq: [], encode_id3: false}

    #@ success for {VorbisComment}
    assert_run A::Song::Activity::Create,  seq: [:model, :prepare_metadata, :encode_cover, :save], target_ctx: {params: {type: "vorbis"}, seq: []}, terminus: :success
    assert_run AA::Song::Activity::Create, seq: [:model, :prepare_metadata, :encode_cover, :save], target_ctx: {params: {type: "vorbis"}, seq: []}, terminus: :success
    assert_run A::Song::Activity::Create,  seq: [:model, :prepare_metadata], terminus: :failure, target_ctx: {params: {type: "vorbis"}, seq: [], prepare_metadata: false}
    assert_run AA::Song::Activity::Create, seq: [:model, :prepare_metadata], terminus: :failure, target_ctx: {params: {type: "vorbis"}, seq: [], prepare_metadata: false}
  end

  #@ raises RuntimeError if we try to wire special terminus.
  it "raises when wiring special termini" do
    exception = assert_raises RuntimeError do
      module B
        class Song; end
          #:dynamic-output
          module Song::Activity
            class Create < Trailblazer::Operation
              step :model
              step Nested(:decide_file_type),
                Output(:unsupported_file_format) => Track(:failure) # error!
              step :save
            end
          end
          #:dynamic-output end
      end
    end # B

    assert_equal exception.message[0..34], %{No `unsupported_file_format` output}
  end

  #@ any internal "special" terminus is mapped to either failure or success.
  #@ FastTrack is converted to Binary outcome.
  module C
    class Song
    end

    module Song::Activity
      Id3Tag        = DocsNestedStaticTest::E::Song::Activity::Id3Tag        # has {fail_fast} and {pass_fast} termini.
      VorbisComment = DocsNestedStaticTest::C::Song::Activity::VorbisComment # has an {End.unsupported_file_format} terminus.
    end

    #:dynamic-unsupported
    module Song::Activity
      class Create < Trailblazer::Operation
        step :model
        step Nested(:decide_file_type) # Run either {Id3Tag} or {VorbisComment}
        step :save
        #~meths
        include T.def_steps(:model, :save)
        def decide_file_type(ctx, params:, **)
          params[:type] == "mp3" ? Id3Tag : VorbisComment
        end
        #~meths end
      end
    end
    #:dynamic-unsupported end
  end # C

  it "{VorbisComment}'s {End.unsupported_file_format} is mapped to {:failure}" do
    #@ {End.pass_fast} goes success for Id3Tag
    assert_invoke C::Song::Activity::Create, seq: %{[:model, :parse, :save]}, params: {type: "mp3"}
    #@ {End.fail_fast} goes failure for Id3Tag
    assert_invoke C::Song::Activity::Create, seq: %{[:model, :parse]}, params: {type: "mp3"}, parse: false, terminus: :failure

    assert_invoke C::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover, :save]}, params: {type: "vorbis"}
    assert_invoke C::Song::Activity::Create, seq: %{[:model, :prepare_metadata]}, params: {type: "vorbis"}, prepare_metadata: false, terminus: :failure
    #@ VorbisComment :unsupported_file_format is mapped to :failure
    assert_invoke C::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover]}, params: {type: "vorbis"}, encode_cover: false, terminus: :failure
  end

  it "is compatible with Debugging API" do
    output, _ = trace A::Song::Activity::Create, params: {type: "mp3"}, seq: []

    assert_equal output, %{TOP
|-- Start.default
|-- model
|-- Nested/decide_file_type
|   |-- Start.default
|   |-- call_dynamic_nested_activity
|   |   `-- DocsNestedStaticTest::A::Song::Activity::Id3Tag
|   |       |-- Start.default
|   |       |-- parse
|   |       |-- encode_id3
|   |       `-- End.success
|   `-- End.success
|-- save
`-- End.success}

    #@ we can look into non-dynamic parts
    assert_equal Trailblazer::Developer::Introspect.find_path(A::Song::Activity::Create,
      ["Nested/decide_file_type", :call_dynamic_nested_activity])[0].task.class.inspect, %{Method}

    #@ we can't look into the dynamic parts
    assert_raises do
      Trailblazer::Developer::Introspect.find_path(A::Song::Activity::Create,
        ["Nested/decide_file_type", :call_dynamic_nested_activity, DocsNestedStaticTest::A::Song::Activity::Id3Tag])[0]
    end
  end
end

class GenericNestedUnitTest < Minitest::Spec
  module ComputeNested
    module_function

    def compute_nested(ctx, what:, **)
      what
    end
  end

  it "allows using multiple Nested() per operation" do
    activity = Class.new(Trailblazer::Operation) do
      step :a
      step Nested(:decide)
      step Nested(:decide), id: "Nested(2)"
      # TODO: with static, too!
      step :b

      def decide(ctx, **)
        DocsNestedStaticTest::A::Song::Activity::Create
      end

      include T.def_steps(:a, :b)
    end

    assert_run activity, seq: [:a, :model, :parse, :encode_id3, :save, :model, :parse, :encode_id3, :save, :b], target_ctx: {params: {type: "mp3"}, seq: []}, terminus: :success
  end

  # TODO: move this to some testing gem? We need it a lot of times.
  def self.step_capturing_visible_variables(ctx, **)
    ctx[:visible] = ctx.keys
  end

  def activity_with_visible_variable
    Class.new(Trailblazer::Operation) do
      step GenericNestedUnitTest.method(:step_capturing_visible_variables)
    end
  end

  def decider_with_visible_variable(ctx, what:, **)
    ctx[:visible_in_decider] << ctx.keys # this is horrible, we're bleeding through to a "global" variable.
    what
  end

  it "nested activity can see everything Nested() can see" do
    sub_activity = activity_with_visible_variable()

    #@ nested can see everything.
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(ComputeNested.method(:compute_nested),
      static: [sub_activity])

    lib_ctx, _ = assert_run activity, target_ctx: {what: sub_activity, dont_look_at_me: true}, seq: nil, terminus: :success
    assert_equal lib_ctx[:target_ctx], {what: sub_activity, dont_look_at_me: true, visible: [:what, :dont_look_at_me]}


    #@ nested can only see {:what}.
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(ComputeNested.method(:compute_nested),
      static: [sub_activity]),
      Trailblazer::Operation.In() => [:what]

    lib_ctx, _ = assert_run activity, target_ctx: {what: sub_activity, dont_look_at_me: true}, seq: nil, terminus: :success
    assert_equal lib_ctx[:target_ctx], {what: sub_activity, dont_look_at_me: true, visible: [:what]}
  end

  it "decider's variables are not discarded" do
    sub_activity    = activity_with_visible_variable()
    compute_nested  = ->(ctx, what:, **) do
      ctx[:please_discard_me] = true  # this bleeds through to all descendents.
      what                            # this however is discarded.
    end

  #@ for Static
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(compute_nested,
      static: [sub_activity])

    #@ nested_activity and top activity can see things from decider.
    expected_variables = {please_discard_me: true, visible: [:what, :please_discard_me], what: sub_activity}

    lib_ctx, _ = assert_run activity, target_ctx: {what: sub_activity}, seq: nil, terminus: :success
    assert_equal lib_ctx[:target_ctx], expected_variables

  #@ for dynamic
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(compute_nested)

    #@ nested_activity and top activity cannot see things from decider.
    lib_ctx, _ = assert_run activity, target_ctx: {what: sub_activity}, seq: nil, terminus: :success
    assert_equal lib_ctx[:target_ctx], expected_variables
  end

  it "without In/Out, decider and nested_activity see the same" do
    sub_activity    = activity_with_visible_variable()
    compute_nested  = method(:decider_with_visible_variable)

  #@ for Static
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(compute_nested,
      static: [sub_activity])

    #@ nested_activity and top activity cannot see things from decider.
    options = {
      what: sub_activity, expected_ctx_variables: {
        visible:            [:seq, :what, :visible_in_decider],
        visible_in_decider: [[:seq, :what, :visible_in_decider]]
      }
    }

    assert_invoke activity, **options, visible_in_decider: []

  #@ for dynamic
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(compute_nested)

    #@ nested_activity and top activity cannot see things from decider.
    assert_invoke activity, **options, visible_in_decider: []
  end

  it "with In/Out, decider sees original ctx, nested_activity sees filtered" do
    # sees {:activity_to_nest}
    decider_with_visible_variable = ->(ctx, activity_to_nest:, **) do
      ctx[:visible_in_decider] << ctx.keys # this is horrible, we're bleeding through to a "global" variable.
      activity_to_nest
    end

    sub_activity    = activity_with_visible_variable()
    compute_nested  = decider_with_visible_variable
    in_out_options  = {
      Trailblazer::Operation.In() => {:activity_to_nest => :what}#,
      # Trailblazer::Operation.In() => [:visible_in_decider]
    }

  #@ for Static
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(compute_nested,
      static: [sub_activity]).merge(in_out_options)

    #@ nested_activity and top activity cannot see things from decider.
    options = {
      please_discard_me: true,
      activity_to_nest: sub_activity, # renamed to {:what}
      expected_ctx_variables: {
        visible:            [:what],
        visible_in_decider: [[:seq, :please_discard_me, :activity_to_nest, :visible_in_decider]]
      }
    }

    assert_invoke activity, **options, visible_in_decider: []

  #@ for dynamic
    activity = Class.new(Trailblazer::Operation)
    activity.step Trailblazer::Operation.Nested(compute_nested).
      merge(in_out_options)

    #@ nested_activity and top activity cannot see things from decider.
    assert_invoke activity, **options, visible_in_decider: []
  end
end
