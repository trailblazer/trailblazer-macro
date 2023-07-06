require "test_helper"

#--
# with proc
class DocsGuardProcTest < Minitest::Spec
  #:proc
  class Create < Trailblazer::Operation
    step Policy::Guard(->(_options, pass:, **) { pass })
    #:pipeonly
    step :process

    def process(options, **)
      options[:x] = true
    end
    #:pipeonly end
  end
  #:proc end

  it { assert_nil Create.(pass: false)[:x] }
  it { assert Create.(pass: true)[:x] }

  #- result object, guard
  it { assert Create.(pass: true)[:"result.policy.default"].success? }
  it { refute Create.(pass: false)[:"result.policy.default"].success? }

  #---
  #- Guard inheritance
  class New < Create
    step Policy::Guard( ->(_options, current_user:, **) { current_user } ), override: true
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
  it { assert Create.(pass: true)[:x] }
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

  it { assert_equal "<Result:false [nil] >", Create.(pass: false).inspect(:x) }
  it { assert_equal "<Result:true [true] >", Create.(pass: true).inspect(:x) }
end

#---
# with name:
class DocsGuardNamedTest < Minitest::Spec
  #:name
  class Create < Trailblazer::Operation
    step Policy::Guard( ->(_options, current_user:, **) { current_user }, name: :user )
    # ...
  end
  #:name end

  it { refute Create.(:current_user => nil   )[:"result.policy.user"].success? }
  it { assert Create.(:current_user => Module)[:"result.policy.user"].success? }

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
    step Policy::Guard( ->(_options, current_user:, **) { current_user == Module } )
  end
  #:di-op end

  it { assert_equal "<Result:true [nil] >", Create.(:current_user => Module).inspect("") }

  it {
    result =
      #:di-call
      Create.(
        :current_user           => Module,
          :"policy.default.eval"  => Trailblazer::Operation::Policy::Guard.build(->(_options, **) { false })
      )
    #:di-call end
    assert_equal "<Result:false [nil] >", result.inspect("")
  }
end

#---
# missing current_user throws exception
class DocsGuardMissingKeywordTest < Minitest::Spec
  class Create < Trailblazer::Operation
    step Policy::Guard( ->(_options, current_user:, **) { current_user == Module } )
  end

  it { assert_raises(ArgumentError) { Create.() } }
  it { assert Create.(:current_user => Module).success? }
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

  it { assert_equal "[>policy.default.eval,>model!]", Trailblazer::Developer.railway(Create) }
  it do
    #:before-pipe
      Trailblazer::Developer.railway(Create, style: :rows) #=>
       # 0 ========================>operation.new
       # 1 ==================>policy.default.eval
       # 2 ===============================>model!
    #:before-pipe end
  end
end
