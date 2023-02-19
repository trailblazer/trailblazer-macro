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

  class Mailer
    def self.send(**options)
      @send_options << options
    end

    class << self
      attr_accessor :send_options
    end
  end

#@ operation has {#composers_for_each}
  module B
    class Song < Struct.new(:id, :title, :band, :composers)
      def self.find_by(id:)
        if id == 2
          return Song.new(id, nil, nil, [Composer.new("Fat Mike", "mike@fat.wreck"), Composer.new("El Hefe")])
        end

        if id == 3
          return Song.new(id, nil, nil, [Composer.new("Fat Mike", "mike@fat.wreck"), Composer.new("El Hefe", "scammer@spam")])
        end

        Song.new(id, nil, nil, [Composer.new("Fat Mike"), Composer.new("El Hefe")])
      end
    end

    #:each
    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        #:each-dataset
        step Each(dataset_from: :composers_for_each, collect: true) {
          step :notify_composers
        }
        #:each-dataset end
        step :rearrange

        # "decider interface"
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        #:iterated-value
        def notify_composers(ctx, index:, item:, **)
          ctx[:value] = [index, item.full_name]
        end
        #:iterated-value end

        #~meths
        def model(ctx, params:, **)
          ctx[:model] = Song.find_by(id: params[:id])
        end

        include T.def_steps(:rearrange)
        #~meths end
      end
    end
    #:each end
  end # B

  it "allows a dataset compute in the hosting activity" do
  #@ {:dataset} is not part of the {ctx}.
    assert_invoke B::Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 1),
        collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      },
      seq: "[:rearrange]"

=begin
    #:collected_from_each
    #~ctx_to_result
    ctx = {params: {id: 1}} # Song 1 has two composers.

    signal, (ctx, _) = Trailblazer::Activity.(Song::Activity::Cover, ctx)

    puts ctx[:collected_from_each] #=> [[0, "Fat Mike"], [1, "El Hefe"]]
    #~ctx_to_result end
    #:collected_from_each end
=end
  end

  module CoverMethods
    def notify_composers(ctx, index:, item:, **)
      ctx[:value] = [index, item.full_name]
    end

    def model(ctx, params:, **)
      ctx[:model] = EachTest::B::Song.find_by(id: params[:id])
    end

    include T.def_steps(:rearrange)
  end

  module ComposersForEach
    def composers_for_each(ctx, model:, **)
      model.composers
    end
  end

#@ operation has dedicated step {#find_composers}
  module C
    class Song < B::Song; end

    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        step :find_composers
        step Each(collect: true) {
            step :notify_composers
        }, In() => {:composers => :dataset}
        step :rearrange

        def find_composers(ctx, model:, **)
          # You could also say {ctx[:dataset] = model.composers},
          # and wouldn't need the In() mapping.
          ctx[:composers] = model.composers
        end
        #~meths
        include CoverMethods
        #~meths end
      end
    end
  end # C

  it "dataset can come from the hosting activity" do
#@ {:dataset} is not part of the outgoing {ctx}.
  assert_invoke B::Song::Activity::Cover, params: {id: 1},
    expected_ctx_variables: {
      model: B::Song.find_by(id: 1),
      collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
    }, seq: "[:rearrange]"
  end

  it "dataset coming via In() from the operation" do
  #@ {:dataset} is not part of the {ctx}.
    assert_invoke C::Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: C::Song.find_by(id: 1),
        composers: [Composer.new("Fat Mike"), Composer.new("El Hefe")],
        collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      }, seq: "[:rearrange]"
  end

#@ {:item_key}
  module E
    class Song < B::Song; end

    Mailer = Class.new(EachTest::Mailer)

    #:composer
    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        #~meths
        step :model
        #:item_key
        step Each(dataset_from: :composers_for_each, item_key: :composer) {
          step :notify_composers
        }
        #:item_key end
        step :rearrange


        # circuit-step interface! "decider interface"
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
        def notify_composers(ctx, index:, composer:, **)
          Mailer.send(to: composer.email, message: "#{index}) You, #{composer.full_name}, have been warned about your song being copied.")
        end
      end
    end
    #:composer end
  end # E

  it "{item_key: :composer}" do
    E::Mailer.send_options = []
    assert_invoke E::Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 1),
        # collected_from_each: ["Fat Mike", "El Hefe"]
      },
      seq: "[:rearrange]"
    assert_equal E::Mailer.send_options, [{:to=>nil, :message=>"0) You, Fat Mike, have been warned about your song being copied."}, {:to=>nil, :message=>"1) You, El Hefe, have been warned about your song being copied."}]
  end

#@ failure in Each
  module F
    class Song < B::Song; end

    class Notify
      def self.send_email(email)
        return if email.nil?
        true
      end
    end

    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        step Each(dataset_from: :composers_for_each, collect: true) {
          step :notify_composers
        }
        step :rearrange

        def notify_composers(ctx, item:, **)
          if Notify.send_email(item.email)
            ctx[:value] = item.email # let's collect all emails that could be sent.
            return true
          else
            return false
          end
        end
        #~meths

        # circuit-step interface! "decider interface"
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
      end
    end
  end # F

  it "failure in Each" do
    assert_invoke F::Song::Activity::Cover, params: {id: 2},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 2),
        collected_from_each: ["mike@fat.wreck", nil],
      },
      seq: "[]",
      terminus: :failure

    Trailblazer::Developer.wtf?(F::Song::Activity::Cover, [{params: {id: 2}, seq: []}])
  end


#@ Each with operation
  module D
    class Song < B::Song; end
    Mailer = Class.new(EachTest::Mailer)

    #:operation-class
    module Song::Activity
      class Notify < Trailblazer::Activity::Railway
        step :send_email

        def send_email(ctx, index:, item:, **)
          Mailer.send(to: item.email, message: "#{index}) You, #{item.full_name}, have been warned about your song being copied.")
        end
      end
    end
    #:operation-class end

    #:operation
    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        step :model
        step Each(Notify, dataset_from: :composers_for_each)
        step :rearrange
        #~meths
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
      end
    end
    #:operation end
  end

  it "Each(Activity::Railway)" do
    D::Mailer.send_options = []
    assert_invoke D::Song::Activity::Cover, params: {id: 1},
      seq:                    "[:rearrange]",
      expected_ctx_variables: {
        model:                D::Song.find_by(id: 1),
        # collected_from_each:  [[0, "Fat Mike"], [1, "El Hefe"],]
      }
    assert_equal D::Mailer.send_options, [{:to=>nil, :message=>"0) You, Fat Mike, have been warned about your song being copied."}, {:to=>nil, :message=>"1) You, El Hefe, have been warned about your song being copied."}]
  end

#@ Each with operation with three outcomes. Notify terminates on {End.spam_email},
#  which is then routed to End.spam_alert in the hosting activity.
# NOTE: this is not documented, yet.
  module G
    class Song < B::Song; end

    module Song::Activity
      class Notify < Trailblazer::Activity::Railway
        terminus :spam_email
        # SpamEmail = Class.new(Trailblazer::Activity::Signal)

        step :send_email, Output(:failure) => Track(:spam_email)

        def send_email(ctx, index:, item:, **)
          return false if item.email == "scammer@spam"
          ctx[:value] = [index, item.full_name]
        end
      end
    end

    module Song::Activity
      class Cover < Trailblazer::Activity::Railway
        terminus :spam_alert

        step :model
        step Each(Notify, dataset_from: :composers_for_each, collect: true),
          Output(:spam_email) => Track(:spam_alert)
        step :rearrange
        #~meths
        def composers_for_each(ctx, model:, **)
          model.composers
        end
        include CoverMethods
        #~meths end
      end
    end
  end

  it "Each(Activity::Railway) with End.spam_email" do
    Trailblazer::Developer.wtf?(G::Song::Activity::Cover, [{params: {id: 3}}, {}])

    assert_invoke G::Song::Activity::Cover, params: {id: 3},
      terminus:                :spam_alert,
      seq:                    "[]",
      expected_ctx_variables: {
        model:                G::Song.find_by(id: 3),
        collected_from_each:  [[0, "Fat Mike"], nil,]
      }
  end
end

#@ Iteration doesn't add anything to ctx when {collect: false}.
class EachCtxDiscardedTest < Minitest::Spec
  Composer  = EachTest::Composer
  Song      = Class.new(EachTest::B::Song)

#@ iterated steps write to ctx, gets discarded.
  module Song::Activity
    class Cover < Trailblazer::Activity::Railway
      step :model
      #:write_to_ctx
      step Each(dataset_from: :composers_for_each) {
        step :notify_composers
        step :write_to_ctx
      }
      #:write_to_ctx end
      step :rearrange

      #:write
      def write_to_ctx(ctx, index:, seq:, **)
        #~meths
        seq << :write_to_ctx

        #~meths end
        ctx[:variable] = index # this is discarded!
      end
      #:write end

      #~meths
      include EachTest::CoverMethods
      include EachTest::ComposersForEach
      #~meths end
    end
  end

  it "discards {ctx[:variable]}" do
    assert_invoke Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: Song.find_by(id: 1),
        # collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      },
      seq: "[:write_to_ctx, :write_to_ctx, :rearrange]"
  end
end

# We add {:collected_from_each} ourselves.
class EachCtxAddsCollectedFromEachTest < Minitest::Spec
  Composer  = EachTest::Composer
  Song      = Class.new(EachTest::B::Song)

  module Song::Activity
    class Cover < Trailblazer::Activity::Railway
      step :model
      step Each(dataset_from: :composers_for_each,

        # all filters called before/after each iteration!
        Inject(:collected_from_each) => ->(ctx, **) { [] }, # this is called only once.
        Out() => ->(ctx, collected_from_each:, **) { {collected_from_each: collected_from_each += [ctx[:value]] } }



      ) {
        step :notify_composers
        step :write_to_ctx
      }
      step :rearrange

      def write_to_ctx(ctx, index:, seq:, item:, **)
        seq << :write_to_ctx

        ctx[:value] = [index, item.full_name]
      end

      #~meths
      include EachTest::CoverMethods
      include EachTest::ComposersForEach
      #~meths end
    end
  end

  it "provides {:collected_from_each}" do
    assert_invoke Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: Song.find_by(id: 1),
        collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      },
      seq: "[:write_to_ctx, :write_to_ctx, :rearrange]"
  end
end

#@ You can use Inject() to compute new variables.
#@ and Out() to compute what goes into the iterated {ctx}.
class EachCtxInOutTest < Minitest::Spec
  Composer  = EachTest::Composer
  Song      = Class.new(EachTest::B::Song)

  module Song::Activity
    class Cover < Trailblazer::Activity::Railway
      step :model
      step Each(dataset_from: :composers_for_each,
        # Inject(always: true) => {
        Inject(:composer_index) => ->(ctx, index:, **) { index },
        # all filters called before/after each iteration!
        Out() => ->(ctx, index:, variable:, **) { {:"composer-#{index}-value" => variable} }





      ) {
        step :notify_composers
        step :write_to_ctx
      }
      step :rearrange

      def write_to_ctx(ctx, composer_index:, model:, **)
        ctx[:variable] = "#{composer_index} + #{model.class.name.split('::').last}"
      end

      #~meths
      include EachTest::CoverMethods
      include EachTest::ComposersForEach
      #~meths end
    end
  end

  it "discards {ctx[:variable]}" do
    assert_invoke Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: Song.find_by(id: 1),
        :"composer-0-value" => "0 + Song",
        :"composer-1-value" => "1 + Song",
      },
      seq: "[:rearrange]"
  end
end

class EachOuterCtxTest < Minitest::Spec

end


#@ {:errors} is first initialized with a default injection,
#@ then passed across iterations.
# TODO: similar test above with {:collected_from_each}.
class EachSharedIterationVariableTest < Minitest::Spec
  Song      = Class.new(EachTest::B::Song)

  #:inject
  module Song::Activity
    class Cover < Trailblazer::Activity::Railway
      step :model
      step Each(dataset_from: :composers_for_each,
        Inject(:messages) => ->(*) { {} },

        # all filters called before/after each iteration!
        Out() => [:messages]
      ) {
        step :write_to_ctx
      }
      step :rearrange

      def write_to_ctx(ctx, item:, messages:, index:, **)
        ctx[:messages] = messages.merge(index => item.full_name)
      end
      #~meths
      include EachTest::CoverMethods
      include EachTest::ComposersForEach
      #~meths end
    end
  end
  #:inject end

  it "passes {ctx[:messages]} across iterations and makes it grow" do
    assert_invoke Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: Song.find_by(id: 1),
        messages: {0=>"Fat Mike", 1=>"El Hefe"}},
      seq: "[:rearrange]"
  end

end

#@ Each without any option
class EachPureTest < Minitest::Spec
  Song      = Class.new(EachTest::B::Song)

  Mailer = Class.new(EachTest::Mailer)

  #:each-pure
  module Song::Activity
    class Cover < Trailblazer::Activity::Railway
      step :model
      #:each-pure-macro
      step Each(dataset_from: :composers_for_each) {
        step :notify_composers
      }
      #:each-pure-macro end
      step :rearrange

      # "decider interface"
      #:dataset_from
      def composers_for_each(ctx, model:, **)
        model.composers
      end
      #:dataset_from end

      #:iterated
      def notify_composers(ctx, index:, item:, **)
        Mailer.send(to: item.email, message: "#{index}) You, #{item.full_name}, have been warned about your song being copied.")
      end
      #:iterated end
      #~meths
      def model(ctx, params:, **)
        ctx[:model] = Song.find_by(id: params[:id])
      end

      include T.def_steps(:rearrange)
      #~meths end
    end
  end
  #:each-pure end

  it "allows a dataset compute in the hosting activity" do
    Mailer.send_options = []
  #@ {:dataset} is not part of the {ctx}.
    assert_invoke Song::Activity::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: Song.find_by(id: 1),
      },
      seq: "[:rearrange]"

    assert_equal Mailer.send_options, [{:to=>nil, :message=>"0) You, Fat Mike, have been warned about your song being copied."}, {:to=>nil, :message=>"1) You, El Hefe, have been warned about your song being copied."}]
  end
end

#~ignore
class EachStrategyComplianceTest < Minitest::Spec
  Song = EachPureTest::Song

  it do
    EachPureTest::Mailer.send_options = []

    #:patch
    cover_patched = Trailblazer::Activity::DSL::Linear::Patch.(
      Song::Activity::Cover,
      ["Each/composers_for_each", "Each.iterate.block"],
      -> { step :log_email }
    )
    #:patch end
    cover_patched.include(T.def_steps(:log_email, :notify_composers))

  #@ Original class isn't changed.
    assert_invoke Song::Activity::Cover, params: {id: 1}, seq: [],
      expected_ctx_variables: {
          model: Song.find_by(id: 1),
        },
      seq: "[:rearrange]"

  #@ Patched class runs
  # Trailblazer::Developer.wtf?(cover_patched, [params: {id: 1}, seq: []])
    assert_invoke cover_patched, params: {id: 1}, seq: [],
      expected_ctx_variables: {
          model: Song.find_by(id: 1),
        },
      seq: "[:notify_composers, :log_email, :notify_composers, :log_email, :rearrange]"
  end


  it "find_path" do
    assert_equal Trailblazer::Developer::Introspect.find_path(Song::Activity::Cover,
      ["Each/composers_for_each", "Each.iterate.block", "invoke_block_activity", :notify_composers])[0].task.inspect,
      %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=notify_composers>}

=begin
#:find_path
node, _ = Trailblazer::Developer::Introspect.find_path(
  Song::Activity::Cover,
  ["Each/composers_for_each", "Each.iterate.block", "invoke_block_activity", :notify_composers])
#=> #<Node ...>
#:find_path end
=end

  end

  it "{#find_path} for Each(Activity) with anonymous class" do
    id = nil

    activity = Class.new(Trailblazer::Activity::Railway) do
      sub_activity = Class.new(Trailblazer::Activity::Railway) do
        step :notify_composers
      end
      id = sub_activity.to_s

      step :model
      step Each(sub_activity, dataset_from: :composers_for_each)
      step :rearrange

      def composers_for_each(ctx, model:, **)
        model.composers
      end
      # include CoverMethods
    end

    node, _activity = Trailblazer::Developer::Introspect.find_path(activity,
      [%{Each/#{id}}, "Each.iterate.#{id}", "invoke_block_activity"])

    assert_equal _activity.class.inspect, "Hash" # container_activity

    #@ inside {invoke_block_activity}
    node, _activity = Trailblazer::Developer::Introspect.find_path(activity,
      [%{Each/#{id}}, "Each.iterate.#{id}", "invoke_block_activity", :notify_composers])

    assert_equal node.task.inspect,
      %{#<Trailblazer::Activity::TaskBuilder::Task user_proc=notify_composers>}
    assert_equal _activity.class.inspect, "Trailblazer::Activity"
  end


  it "tracing" do
    EachPureTest::Mailer.send_options = []
    #:wtf
    Trailblazer::Developer.wtf?(Song::Activity::Cover, [{
      params: {id: 1},
      #~meths
      seq: []
      #~meths end
    }])
    #:wtf end
  end
end


#@ dataset: []
class EachEmptyDatasetTest < Minitest::Spec
  it do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() {
        step :raise
      }
    end

    assert_invoke activity, dataset: []
  end
end

class EachIDTest < Minitest::Spec
  class Validate < Trailblazer::Activity::Railway
  end

  it "assigns IDs via {Macro.id_for}" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each() {}
      step Each(Validate)
      step Each() {}, id: "Each-1"
      step Each(dataset_from: :composers_for_each) {}
    end

    assert_equal Trailblazer::Developer::Introspect.find_path(activity, ["Each/EachIDTest::Validate"])[0].id, "Each/EachIDTest::Validate"
    assert_equal Trailblazer::Developer::Introspect.find_path(activity, ["Each-1"])[0].id,                    "Each-1"
    assert_equal Trailblazer::Developer::Introspect.find_path(activity, ["Each/composers_for_each"])[0].id,   "Each/composers_for_each"

    assert_match /Each\/\w+/, Trailblazer::Activity::Introspect::TaskMap(activity).values[1].id
  end
end

class DocsEachUnitTest < Minitest::Spec
  module ComputeItem
    def compute_item(ctx, item:, index:, **)
      ctx[:value] = "#{item}-#{index.inspect}"
    end
  end

  def self.block
    -> (*){
      step :compute_item
    }
  end

  it "with Trace" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      include T.def_steps(:a, :b)
      include ComputeItem

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
    activity = Trailblazer::Macro.Each(collect: true, &DocsEachUnitTest.block)[:task]

    my_exec_context = Class.new do
      include ComputeItem
    end.new

    ctx = {
      dataset: [1,2,3]
    }

    # signal, (_ctx, _) = Trailblazer::Activity::TaskWrap.invoke(activity, [ctx])
    signal, (_ctx, _) = Trailblazer::Developer.wtf?(activity, [ctx], exec_context: my_exec_context)
    assert_equal _ctx[:collected_from_each], ["1-0", "2-1", "3-2"]
  end


  it "accepts iterated {block}" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      include ComputeItem

      step Each(collect: true) { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item
      }
    end

    Trailblazer::Developer.wtf?(activity, [{dataset: ["one", "two", "three"]}, {}])

    assert_invoke activity, dataset: ["one", "two", "three"], expected_ctx_variables: {collected_from_each: ["one-0", "two-1", "three-2"]}
  end

  it "can see the entire ctx" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      def compute_item_with_current_user(ctx, item:, index:, current_user:, **)
        ctx[:value] = "#{item}-#{index.inspect}-#{current_user}"
      end

      step Each(collect: true) { # expects {:dataset}
        step :compute_item_with_current_user
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
      step Each(collect: true) { # expects {:dataset} # NOTE: use {} not {do ... end}
        step :compute_item, In() => {:current_user => :user}, In() => [:item, :index]
      }

      def compute_item(ctx, item:, index:, user:, **)
        ctx[:value] = "#{item}-#{index.inspect}-#{user}"
      end
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
      step Each(nested_activity, collect: true)  # expects {:dataset}
    end
    # Trailblazer::Developer.wtf?(activity, [{dataset: ["one", "two", "three"]}, {}])

    assert_invoke activity, dataset: ["one", "two", "three"], expected_ctx_variables: {collected_from_each: ["one-0", "two-1", "three-2"]}
  end

  it "doesn't override an existing ctx[:index]" do
   activity = Class.new(Trailblazer::Activity::Railway) do
      include T.def_steps(:a, :b)
      include ComputeItem

      step Each(collect: true, &DocsEachUnitTest.block), id: "Each/1"
      step :b
      def b(ctx, seq:, index:, **)
        ctx[:seq] = seq + [index]
      end

    end

    assert_invoke activity, dataset: [1,2,3], index: 9,
      expected_ctx_variables: {collected_from_each: ["1-0", "2-1", "3-2"]},
      seq: "[9]"
  end

  it "stops iterating when failure" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each(collect: true) {
        step :check
      }
      step :a

      include T.def_steps(:a)
      def check(ctx, item:, **)
        ctx[:value] = item.to_s #@ always collect the value, even in failure case.

        return false if item >= 3
        true
      end
    end

    #@ all works
    assert_invoke activity, dataset: [1,2],
      expected_ctx_variables: {collected_from_each: ["1", "2"]},
      seq: "[:a]"

    #@ fail at 3 but still collect 3rd iteration!
    Trailblazer::Developer.wtf?(activity, [{dataset: [1,2,3]}, {}])
    assert_invoke activity, dataset: [1,2,3],
      expected_ctx_variables: {collected_from_each: ["1", "2", "3"]},
      seq: "[]",
      terminus: :failure

    #@ fail at 3, skip 4
    assert_invoke activity, dataset: [1,2,3,4],
      expected_ctx_variables: {collected_from_each: ["1", "2", "3"]},
      seq: "[]",
      terminus: :failure
  end
end


class EachInEachTest < Minitest::Spec
  it "what" do
    activity = Class.new(Trailblazer::Activity::Railway) do
      step Each(item_key: :outer) {
        step :capture_outer

        step Each(dataset_from: :inner_dataset, item_key: :inner) {
          step :capture_inner
        }
      }

      def capture_outer(ctx, outer:, **)
        ctx[:seq] << outer
      end

      def capture_inner(ctx, inner:, **)
        ctx[:seq] << inner
      end

      def inner_dataset(ctx, outer:, **)
        outer.collect { |i| i * 10 }
      end
    end

    assert_invoke activity, dataset: [[1,2],[3,4],[5,6]],
      seq: %{[[1, 2], 10, 20, [3, 4], 30, 40, [5, 6], 50, 60]}
  end
end
