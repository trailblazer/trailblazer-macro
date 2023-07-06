require "test_helper"

class PolicyTest < Minitest::Spec
  Song = Struct.new(:id) do
    def self.find(id); new(id) end
  end

  class Auth
    def initialize(user, model); @user, @model = user, model end
    def only_user?; @user == Module && @model.nil? end
    def user_object?; @user == Object end
    def user_and_model?; @user == Module && @model.class == Song end
    def inspect; "<Auth: user:#{@user.inspect}, model:#{@model.inspect}>" end
  end

  #---
  # Instance-level: Only policy, no model
  class Create < Trailblazer::Operation
    step Policy::Pundit( Auth, :only_user? )
    step :process

    def process(options, **)
      options[:process] = true
    end
  end

  # successful.
  it do
    result = Create.(params: {}, current_user: Module)
    assert result[:process]
    #- result object, policy
    assert result[:"result.policy.default"].success?
    assert_nil result[:"result.policy.default"][:message]
    assert_equal "<Auth: user:Module, model:nil>", result[:"policy.default"].inspect
  end
  # breach.
  it do
    result = Create.(params: {}, current_user: nil)
    assert_nil result[:process]
    refute result[:"result.policy.default"].success?
    assert_equal "Breach", result[:"result.policy.default"][:message]
  end
  # inject different policy.Condition  it { Create.(params: {}, current_user: Object, "policy.default.eval" => Trailblazer::Operation::Policy::Pundit::Condition.new(Auth, :user_object?))["process"].must_equal true }
  it { assert_nil Create.(params: {}, current_user: Module, :"policy.default.eval" => Trailblazer::Operation::Policy::Pundit::Condition.new(Auth, :user_object?))[:process] }

  it { assert_nil Create.(params: {}, current_user: Module, :"policy.default.eval" => Trailblazer::Operation::Policy::Pundit::Condition.new(Auth, :user_object?))[:process] }

  #---
  # inheritance, adding Model
  class Show < Create
    step Model( Song, :new ), before: :"policy.default.eval"
  end

  it { assert_equal "[>model.build,>policy.default.eval,>process]", Trailblazer::Developer.railway(Show) }

  # invalid because user AND model.
  it do
    result = Show.(params: {}, current_user: Module)
    assert_nil result[:process]
    assert_match(/#<struct PolicyTest::Song id=nil>/, result[:model].inspect)
  end

  # valid because new policy.
  it do
    # puts Show["pipetree"].inspect
    result = Show.(params: {}, current_user: Module, :"policy.default.eval" => Trailblazer::Operation::Policy::Pundit::Condition.new(Auth, :user_and_model?))
    assert result[:process]
    assert_match(/#<struct PolicyTest::Song id=nil>/, result[:"model"].inspect)
    assert_match(/<Auth: user:Module, model:#<struct PolicyTest::Song id=nil>>/, result[:"policy.default"].inspect)
  end

  ##--
  # TOOOODOOO: Policy and Model before Build ("External" or almost Resolver)
  class Edit < Trailblazer::Operation
    step Model Song, :find
    step Policy::Pundit( Auth, :user_and_model? )
    step :process

    def process(options, **)
      options[:process] = true
    end
  end

  # successful.
  it do
    result = Edit.(params: { id: 1 }, current_user: Module)
    assert result[:process]
    assert_equal result[:model].inspect, %{#<struct PolicyTest::Song id=1>}
    assert result[:"result.policy.default"].success?
    assert_nil result[:"result.policy.default"][:message]
    assert_match(/<Auth: user:Module, model:#<struct PolicyTest::Song id=1>>/, result[:"policy.default"].inspect)
  end

  # breach.
  it do
    result = Edit.(params: { id: 4 }, current_user: nil)
    assert_match(/<struct PolicyTest::Song id=4>/, result[:model].inspect)
    assert_nil result[:process]
    refute result[:"result.policy.default"].success?
    assert_equal "Breach", result[:"result.policy.default"][:message]
  end
end
