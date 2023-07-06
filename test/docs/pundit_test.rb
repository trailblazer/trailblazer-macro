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
  it { assert_equal Create.(params: {}, current_user: Module).inspect(:model), %{<Result:true [#<struct DocsPunditProcTest::Song id=nil>] >} }
  it { assert_equal Create.(params: {}                          ).inspect(:model), %{<Result:false [#<struct DocsPunditProcTest::Song id=nil>] >} }

  it do
  #:pundit-result
  result = Create.(params: {}, current_user: Module)
  result[:"result.policy.default"].success? #=> true
  result[:"result.policy.default"][:policy] #=> #<MyPolicy ...>
  #:pundit-result end
  assert result[:"result.policy.default"].success?
  assert result[:"result.policy.default"][:policy].is_a?(MyPolicy)
  end

  #---
  #- override
  class New < Create
    step Policy::Pundit( MyPolicy, :new? ), override: true
  end

  it { assert_equal "[>model.build,>policy.default.eval]", Trailblazer::Developer.railway(New) }

  it { assert_equal "<Result:true [#<struct DocsPunditProcTest::Song id=nil>] >", New.(params: {}, current_user: Class).inspect(:model) }

  it { assert_equal "<Result:false [#<struct DocsPunditProcTest::Song id=nil>] >", New.(params: {}, current_user: nil).inspect(:model) }

  #---
  #- override with :name
  class Edit < Trailblazer::Operation
    step Policy::Pundit( MyPolicy, :create?, name: "first" )
    step Policy::Pundit( MyPolicy, :new?,    name: "second" )
  end

  class Update < Edit
    step Policy::Pundit( MyPolicy, :new?, name: "first" ), override: true
  end

  it { assert_equal "[>policy.first.eval,>policy.second.eval]", Trailblazer::Developer.railway(Edit) }
  it { assert_equal "<Result:false [nil] >", Edit.(params: {}, current_user: Class).inspect(:model) }
  it { assert_equal "[>policy.first.eval,>policy.second.eval]", Trailblazer::Developer.railway(Update) }
  it { assert_equal "<Result:true [nil] >", Update.(params: {}, current_user: Class).inspect(:model) }

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
    assert_equal "<Result:true [nil] >", result.inspect("")
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
  assert result[:"result.policy.after_model"].success? }
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
#   it { assert Create.(params: {}, current_user: Module)["x"] }
#   it { Create.(params: {}                          )["x"].must_be_nil }
# end



# TODO:
#policy.default
