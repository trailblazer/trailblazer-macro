# THIS FILE IS AUTOGENERATED FROM trailblazer-macro/test/docs/each_test.rb
require "test_helper"


# step Macro::Each(:report_templates, key: :report_template) {
#   step Subprocess(ReportTemplate::Update), input: :input_report_template
#   left :set_report_template_errors
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
    module Song::Operation
      class Cover < Trailblazer::Operation
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
    assert_invoke B::Song::Operation::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 1),
        collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
      },
      seq: "[:rearrange]"

=begin
    #:collected_from_each
    #~ctx_to_result
    ctx = {params: {id: 1}} # Song 1 has two composers.

    result = Song::Operation::Cover.(ctx)

    puts result[:collected_from_each] #=> [[0, "Fat Mike"], [1, "El Hefe"]]
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

    module Song::Operation
      class Cover < Trailblazer::Operation
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
  assert_invoke B::Song::Operation::Cover, params: {id: 1},
    expected_ctx_variables: {
      model: B::Song.find_by(id: 1),
      collected_from_each: [[0, "Fat Mike"], [1, "El Hefe"],]
    }, seq: "[:rearrange]"
  end

  it "dataset coming via In() from the operation" do
  #@ {:dataset} is not part of the {ctx}.
    assert_invoke C::Song::Operation::Cover, params: {id: 1},
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
    module Song::Operation
      class Cover < Trailblazer::Operation
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

    assert_invoke E::Song::Operation::Cover, params: {id: 1},
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

    module Song::Operation
      class Cover < Trailblazer::Operation
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
    assert_invoke F::Song::Operation::Cover, params: {id: 2},
      expected_ctx_variables: {
        model: B::Song.find_by(id: 2),
        collected_from_each: ["mike@fat.wreck", nil],
      },
      seq: "[]",
      terminus: :failure

    Trailblazer::Developer.wtf?(F::Song::Operation::Cover, [{params: {id: 2}, seq: []}])
  end


#@ Each with operation
  module D
    class Song < B::Song; end
    Mailer = Class.new(EachTest::Mailer)

    #:operation-class
    module Song::Operation
      class Notify < Trailblazer::Operation
        step :send_email

        def send_email(ctx, index:, item:, **)
          Mailer.send(to: item.email, message: "#{index}) You, #{item.full_name}, have been warned about your song being copied.")
        end
      end
    end
    #:operation-class end

    #:operation
    module Song::Operation
      class Cover < Trailblazer::Operation
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

    assert_invoke D::Song::Operation::Cover, params: {id: 1},
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

    module Song::Operation
      class Notify < Trailblazer::Operation
        terminus :spam_email
        # SpamEmail = Class.new(Trailblazer::Operation::Signal)

        step :send_email, Output(:failure) => Track(:spam_email)

        def send_email(ctx, index:, item:, **)
          return false if item.email == "scammer@spam"
          ctx[:value] = [index, item.full_name]
        end
      end
    end

    module Song::Operation
      class Cover < Trailblazer::Operation
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
    Trailblazer::Developer.wtf?(G::Song::Operation::Cover, [{params: {id: 3}}, {}])

    assert_invoke G::Song::Operation::Cover, params: {id: 3},
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
  module Song::Operation
    class Cover < Trailblazer::Operation
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
    assert_invoke Song::Operation::Cover, params: {id: 1},
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

  module Song::Operation
    class Cover < Trailblazer::Operation
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
    assert_invoke Song::Operation::Cover, params: {id: 1},
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

  module Song::Operation
    class Cover < Trailblazer::Operation
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
    assert_invoke Song::Operation::Cover, params: {id: 1},
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
  module Song::Operation
    class Cover < Trailblazer::Operation
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
    assert_invoke Song::Operation::Cover, params: {id: 1},
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
  module Song::Operation
    class Cover < Trailblazer::Operation
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
    assert_invoke Song::Operation::Cover, params: {id: 1},
      expected_ctx_variables: {
        model: Song.find_by(id: 1),
      },
      seq: "[:rearrange]"

    assert_equal Mailer.send_options, [{:to=>nil, :message=>"0) You, Fat Mike, have been warned about your song being copied."}, {:to=>nil, :message=>"1) You, El Hefe, have been warned about your song being copied."}]
  end
end

