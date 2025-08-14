require "test_helper"

  #:policy
  class MyPolicy
    def initialize(user, model)
      @user, @model = user, model
    end

    def create?
      @user == Module && @model.id.nil?
    end

    def new?
      @user == Class
    end
  end
  #:policy end

#--
# with policy
class DocsPunditProcTest < Minitest::Spec
  Song = Struct.new(:id)

  #:pundit
  class Create < Trailblazer::Operation
    step Model( Song, :new )
    step Policy::Pundit( MyPolicy, :create? )
    # ...
  end
  #:pundit end

  it { assert_equal Trailblazer::Developer.railway(Create), %{[>model.build,>policy.default.eval]} }
  it {
    result = Create.(params: {}, current_user: Module)
    assert_equal result[:model].inspect, %(#<struct DocsPunditProcTest::Song id=nil>)
    assert result.success?
  }
  it {
    result = Create.(params: {})
    assert_equal result[:model].inspect, %(#<struct DocsPunditProcTest::Song id=nil>)
    assert result.failure?
  }

  it do
  #:pundit-result
    result = Create.(params: {}, current_user: Module)
    result[:"result.policy.default"].success? #=> true
    result[:"result.policy.default"][:policy] #=> #<MyPolicy ...>
  #:pundit-result end
    assert_equal result[:"result.policy.default"].success?, true
    assert_equal result[:"result.policy.default"][:policy].is_a?(MyPolicy), true
  end

  #---
  #- override
  class New < Create
    step Policy::Pundit( MyPolicy, :new? ), replace: :"policy.default.eval"
  end

  it { assert_equal Trailblazer::Developer.railway(New), %{[>model.build,>policy.default.eval]} }
  it {
    result = New.(params: {}, current_user: Class )
    assert_equal result[:model].inspect, %(#<struct DocsPunditProcTest::Song id=nil>)
    assert result.success?
  }
  it {
    result = New.(params: {}, current_user: nil )
    assert_equal result[:model].inspect, %(#<struct DocsPunditProcTest::Song id=nil>)
    assert result.failure?
  }

  #---
  #- override with :name
  class Edit < Trailblazer::Operation
    step Policy::Pundit( MyPolicy, :create?, name: "first" )
    step Policy::Pundit( MyPolicy, :new?,    name: "second" )
  end

  class Update < Edit
    step Policy::Pundit( MyPolicy, :new?, name: "first" ), override: true
  end

  it { assert_equal Trailblazer::Developer.railway(Edit), %{[>policy.first.eval,>policy.second.eval]} }
  it {
    result = Edit.(params: {}, current_user: Class)
    assert_equal result[:model].inspect, %(nil)
    assert result.failure?
  }
  it { assert_equal Trailblazer::Developer.railway(Update), %{[>policy.first.eval,>policy.second.eval]} }
  it {
    result = Update.(params: {}, current_user: Class)
    assert_equal result[:model].inspect, %(nil)
    assert result.success?
  }

  #---
  # dependency injection
  class AnotherPolicy < MyPolicy
    def create?
      true
    end
  end

  it {
    result =
  #:di-call
  Create.(params: {},
    current_user:            Module,
    :"policy.default.eval" => Trailblazer::Operation::Policy::Pundit.build(AnotherPolicy, :create?)
  )
  #:di-call end
    assert_equal result[:model].inspect, %(#<struct DocsPunditProcTest::Song id=nil>)
    assert result.success?
  }
end

#-
# with name:
class PunditWithNameTest < Minitest::Spec
  Song = Struct.new(:id)

  #:name
  class Create < Trailblazer::Operation
    step Model( Song, :new )
    step Policy::Pundit( MyPolicy, :create?, name: "after_model" )
    # ...
  end
  #:name end

  it {
  #:name-call
  result = Create.(params: {}, current_user: Module)
  result[:"result.policy.after_model"].success? #=> true
  #:name-call end
  assert_equal result[:"result.policy.after_model"].success?, true }
end

#---
# class-level guard
# class DocsGuardClassLevelTest < Minitest::Spec
#   #:class-level
#   class Create < Trailblazer::Operation
#     step Policy::Guard[ ->(options) { options["current_user"] == Module } ],
#       before: "operation.new"
#     #~pipe--only
#     step ->(options) { options["x"] = true }
#     #~pipe--only end
#   end
#   #:class-level end

#   it { Create.(); Create["result.policy"].must_be_nil }
#   it { Create.(params: {}, current_user: Module)["x"], true }
#   it { Create.(params: {}                          )["x"].must_be_nil }
# end



# TODO:
#policy.default
