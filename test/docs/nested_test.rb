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
    #@ success for VorbisComment
    assert_invoke A::Song::Activity::Create, seq: %{[:model, :prepare_metadata, :encode_cover, :save]}, params: {type: "vorbis"}


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
  end



  let(:edit) do
    Class.new(Trailblazer::Operation) do
      step :c

      include T.def_steps(:c)
    end
  end

  let(:update) do
    Class.new(Trailblazer::Operation) do
      step :d
      include T.def_steps(:d)
    end
  end

  class Validate < Trailblazer::Operation
    step :validate
    # ... more steps ...
    include T.def_steps(:validate)
  end

  class JsonValidate < Validate
    step :json
    include T.def_steps(:json)
  end

  it "Nested(Edit), without any options" do
      module A

        create =
        #:nested
        class Create < Trailblazer::Operation
          step :create
          step Nested(Validate)
          step :save
          #~meths
          include T.def_steps(:create, :save)
          #~meths end
        end
        #:nested end

        # this will print a DEPRECATION warning.
      # success
        create.(seq: []).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}
      # failure in Nested
        create.(seq: [], validate: false).inspect(:seq).must_equal %{<Result:false [[:create, :validate]] >}
      end
  end

  it "Nested(Edit), with Output rewiring" do
    edit = self.edit

    create = Class.new(Trailblazer::Operation) do
      step :a
      step Nested( edit ), Output(:failure) => Track(:success)
      step :b

      include T.def_steps(:a, :b)
    end

  # success
    create.(seq: []).inspect(:seq).must_equal %{<Result:true [[:a, :c, :b]] >}
  # failure in Nested
    create.(seq: [], c: false).inspect(:seq).must_equal %{<Result:true [[:a, :c, :b]] >}
  end

  module B
    #:nested-dynamic
    class Create < Trailblazer::Operation
      step :create
      step Nested(:compute_nested)
      step :save

      def compute_nested(ctx, params:, **)
        params.is_a?(Hash) ? Validate : JsonValidate
      end
      #~meths
      include T.def_steps(:create, :save)
      #~meths end
    end
  end

  it "Nested(:method)" do
      #:nested-dynamic end
    # `edit` and `update` can be called from Nested()

  # edit/success
    B::Create.(seq: [], params: {}).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}

  # update/success
    B::Create.(seq: [], params: nil).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :json, :save]] >}


# wiring of fail:
  # edit/failure
    B::Create.(seq: [], params: {}, validate: false).inspect(:seq).must_equal %{<Result:false [[:create, :validate]] >}
  # update/failure
    B::Create.(seq: [], params: nil, json: false).inspect(:seq).must_equal %{<Result:false [[:create, :validate, :json]] >}
  end

  it "Nested(:method) with tracing" do
    stack, signal, (ctx, _) = Trailblazer::Developer::Trace.invoke(B::Create, [{seq: [], params: {}}])

puts stack.to_a[5]

        assert_equal Trailblazer::Developer::Trace::Present.(stack,

      # compute_runtime_id: my_compute_runtime_id,

      # node_options: {stack.to_a[0] => {label: "<a-Each-b>"}}
          ), %{<a-Each-b>
|-- Start.default

`-- End.success}

  #@ compile time
  #@ make sure we can find tasks/compile-time artifacts in Each by using their {compile_id}.
    assert_equal Trailblazer::Developer::Introspect.find_path(activity,
      ["Each/1", "Each.iterate.block", "invoke_block_activity", :compute_item])[0].task.inspect,
      %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=compute_item>}
  end

  it "Nested(:method), input: :my_input" do
    module C
      #:nested-dynamic
      class Create < Trailblazer::Operation
        step :create
        step Nested(:compute_nested), input: ->(ctx, *) {{foo: :bar, seq: ctx[:seq]}}
        step :save

        def compute_nested(ctx, params:, **)
          params.is_a?(Hash) ? Validate : JsonValidate
        end

        #~meths
        include T.def_steps(:create, :save)
        #~meths end
      end
      #:nested-dynamic end

    # `edit` and `update` can be called from Nested()
    end

    C::Create.(seq: [], params: {}).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}
    C::Create.(seq: [], params: nil).inspect(:seq).must_equal %{<Result:true [[:create, :validate, :json, :save]] >}
  end

  it "Nested(:method), with pass_fast returned from nested" do
    class JustPassFast < Trailblazer::Operation
      step :just_pass_fast, pass_fast: true
      include T.def_steps(:just_pass_fast)
    end

    module D

      create =
      #:nested-with-pass-fast
      class Create < Trailblazer::Operation

        def compute_nested(ctx, **)
          JustPassFast
        end

        step :create
        step Nested(:compute_nested)
        step :save
        #~meths
        include T.def_steps(:create, :save)
        #~meths end
      end
      #:nested-with-pass-fast end

      #= {#save} is still called because the {End.pass_fast} terminus is automatically wired to
      #= the success "output" of Nested().
      create.(seq: []).inspect(:seq).must_equal %{<Result:true [[:create, :just_pass_fast, :save]] >}
    end
  end

  it "Nested(:method, auto_wire: *activities) with :pass_fast => End()" do
    module E
      class JsonValidate < Trailblazer::Operation
        step :validate, Output(:failure) => End(:invalid_json)
        step :save
        include T.def_steps(:validate, :save)
      end

      #:nested-with-auto-wire
      class Create < Trailblazer::Operation
        step :create
        step Nested(:compute_nested, auto_wire: [Validate, JsonValidate]),
          Output(:invalid_json) => End(:jsoned)

        #~meths
        def compute_nested(ctx, what:, **)
          what
        end

        include T.def_steps(:create)
        #~meths end
      end
      #:nested-with-auto-wire end


    #@ nested {JsonValidate} ends on {End.success}
      result = Create.(seq: [], what: JsonValidate, validate: true)

      result.inspect(:seq).must_equal %{<Result:true [[:create, :validate, :save]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}

    #@ nested {JsonValidate} ends on {End.invalid_json} because validate fails.
      result = Create.(seq: [], what: JsonValidate, validate: false)

      result.inspect(:seq).must_equal %{<Result:false [[:create, :validate]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::End semantic=:jsoned>}

    #@ nested {JsonValidate} ends on {End.failure} because save fails.
      result = Create.(seq: [], what: JsonValidate, save: false)

      result.inspect(:seq).must_equal %{<Result:false [[:create, :validate, :save]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Failure semantic=:failure>}

    #@ nested {Validate} ends on {End.failure} because validate fails.
      result = Create.(seq: [], what: Validate, validate: false)

      result.inspect(:seq).must_equal %{<Result:false [[:create, :validate]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Failure semantic=:failure>}

    #@ nested {Validate} ends on {End.success}.
      result = Create.(seq: [], what: Validate)

      result.inspect(:seq).must_equal %{<Result:true [[:create, :validate]] >}
      result.event.inspect.must_equal %{#<Trailblazer::Activity::Railway::End::Success semantic=:success>}
    end
  end
end

# TODO: test with :input/:output, tracing
# =end
