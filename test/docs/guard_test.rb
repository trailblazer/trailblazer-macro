require "test_helper"

#--
# with proc
class DocsGuardProcTest < Minitest::Spec
  #:proc
  class Create < Trailblazer::Operation
    step Policy::Guard(->(options, pass:, **) { pass })
    #:pipeonly
    step :process

    def process(options, **)
      options[:x] = true
    end
    #:pipeonly end
  end
  #:proc end

  it { assert_nil Create.(pass: false)[:x] }

  it { assert_equal Create.(pass: true)[:x], true }

  #- result object, guard
  it { assert_equal Create.(pass: true)[:"result.policy.default"].success?, true }
  it { assert_equal Create.(pass: false)[:"result.policy.default"].success?, false }

  #---
  #- Guard inheritance
  class New < Create
    step Policy::Guard( ->(options, current_user:, **) { current_user } ), replace: :"policy.default.eval"
  end

  it { assert_equal Trailblazer::Developer.railway(New), %{[>policy.default.eval,>process]} }
end

#---
# with Callable
class DocsGuardTest < Minitest::Spec
  #:callable
  class MyGuard
    def call(options, pass:, **)
      pass
    end
  end
  #:callable end

  #:callable-op
  class Create < Trailblazer::Operation
    step Policy::Guard( MyGuard.new )
    #:pipe-only
    step :process

    #~methods
    def process(options, **)
      options[:x] = true
    end
    #~methods end
    #:pipe-only end
  end
  #:callable-op end

  it { assert_nil Create.(pass: false)[:x] }

  it { assert_equal Create.(pass: true)[:x], true }
end

#---
# with method
class DocsGuardMethodTest < Minitest::Spec
  #:method
  class Create < Trailblazer::Operation
    step Policy::Guard( :pass? )

    def pass?(options, pass:, **)
      pass
    end
    #~pipe-onlyy
    step :process
    #~methods
    def process(options, **)
      options[:x] = true
    end
    #~methods end
    #~pipe-onlyy end
  end
  #:method end

  it { assert_equal Create.(pass: false).inspect(:x), %{<Result:false [nil] >} }
  it { assert_equal Create.(pass: true).inspect(:x), %{<Result:true [true] >} }
end

#---
# with name:
class DocsGuardNamedTest < Minitest::Spec
  #:name
  class Create < Trailblazer::Operation
    step Policy::Guard( ->(options, current_user:, **) { current_user }, name: :user )
    # ...
  end
  #:name end

  it { assert_equal Create.(:current_user => nil   )[:"result.policy.user"].success?, false }
  it { assert_equal Create.(:current_user => Module)[:"result.policy.user"].success?, true }

  it {
  #:name-result
  result = Create.(:current_user => true)
  result[:"result.policy.user"].success? #=> true
  #:name-result end
  }
end

#---
# dependency injection
class DocsGuardInjectionTest < Minitest::Spec
  #:di-op
  class Create < Trailblazer::Operation
    step Policy::Guard( ->(options, current_user:, **) { current_user == Module } )
  end
  #:di-op end

  it { assert_equal Create.(:current_user => Module).inspect(""), %{<Result:true [nil] >} }
  it {
    result =
  #:di-call
  Create.(
    :current_user           => Module,
    :"policy.default.eval"  => Trailblazer::Operation::Policy::Guard.build(->(options, **) { false })
  )
  #:di-call end
    assert_equal result.inspect(""), %{<Result:false [nil] >} }
end

#---
# missing current_user throws exception
class DocsGuardMissingKeywordTest < Minitest::Spec
  class Create < Trailblazer::Operation
    step Policy::Guard( ->(options, current_user:, **) { current_user == Module } )
  end

  it { assert_raises(ArgumentError) { Create.() } }
  it { assert_equal Create.(:current_user => Module).success?, true }
end

#---
# before:
class DocsGuardPositionTest < Minitest::Spec
  #:before
  class Create < Trailblazer::Operation
    step :model!
    step Policy::Guard( :authorize! ),
      before: :model!
  end
  #:before end

  it { assert_equal Trailblazer::Developer.railway(Create), %{[>policy.default.eval,>model!]} }
  it do
    #:before-pipe
      Trailblazer::Developer.railway(Create, style: :rows) #=>
       # 0 ========================>operation.new
       # 1 ==================>policy.default.eval
       # 2 ===============================>model!
    #:before-pipe end
  end
end
