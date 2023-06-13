require "test_helper"

class IfMacroTest < Minitest::Spec
  class Song
    module Activity
      class Upload < Trailblazer::Activity::FastTrack
        step :model
        step If(:condition) {
          step :update   # this changes the database.
          step :transfer # this might even break!
        }
        step :notify
        fail :log_error
        #~meths
        include T.def_steps(:model, :condition, :update, :transfer, :notify, :log_error)
        #~meths end
      end
    end
  end

  it do
    assert_invoke Song::Activity::Upload, condition: true, seq: "[:model, :condition, :update, :transfer, :notify]", expected_ctx_variables: { "result.condition.default": true }
    assert_invoke Song::Activity::Upload, condition: false, seq: "[:model, :condition, :notify]", expected_ctx_variables: { "result.condition.default": false }
    assert_invoke Song::Activity::Upload, condition: true, transfer: false, seq: "[:model, :condition, :update, :transfer, :log_error]", terminus: :failure, expected_ctx_variables: { "result.condition.default": true }
  end
end

class IfWithCustomNameTest < Minitest::Spec
  class Song
    module Activity
      class Upload < Trailblazer::Activity::FastTrack
        step If(:condition, name: :custom_name) {
          step :update   # this changes the database.
        }
        #~meths
        include T.def_steps(:condition, :update)
        #~meths end
      end
    end
  end

  it do
    assert_invoke Song::Activity::Upload, condition: true, seq: "[:condition, :update]", expected_ctx_variables: { "result.condition.custom_name": true }
    assert_invoke Song::Activity::Upload, condition: false, seq: "[:condition]", expected_ctx_variables: { "result.condition.custom_name": false }
  end
end

class IfWithProcTest < Minitest::Spec
  class Song
    module Activity
      class Upload < Trailblazer::Activity::FastTrack
        step If(->(_ctx, condition:, **) { condition }) {
          step :update   # this changes the database.
        }
        #~meths
        include T.def_steps(:update)
        #~meths end
      end
    end
  end

  it do
    assert_invoke Song::Activity::Upload, condition: true, seq: "[:update]", expected_ctx_variables: { "result.condition.default": true }
    assert_invoke Song::Activity::Upload, condition: false, seq: "[]", expected_ctx_variables: { "result.condition.default": false }
  end
end

class IfWithCallableTest < Minitest::Spec
  class Song
    module Activity
      class Upload < Trailblazer::Activity::FastTrack
        class Callable
          def self.call(_ctx, condition:, **)
            condition
          end
        end

        step If(Callable) {
          step :update   # this changes the database.
        }
        #~meths
        include T.def_steps(:update)
        #~meths end
      end
    end
  end

  it do
    assert_invoke Song::Activity::Upload, condition: true, seq: "[:update]", expected_ctx_variables: { "result.condition.default": true }
    assert_invoke Song::Activity::Upload, condition: false, seq: "[]", expected_ctx_variables: { "result.condition.default": false }
  end
end

class IfWithNestedIfTest < Minitest::Spec
  class Song
    module Activity
      class Upload < Trailblazer::Activity::FastTrack
        step If(:condition) {
          step :update   # this changes the database.
          step If(:nested_condition, name: :nested) {
            step :notify
          }
          step :finalize
        }
        #~meths
        include T.def_steps(:condition, :update, :nested_condition, :notify, :finalize)
        #~meths end
      end
    end
  end

  it do
    assert_invoke Song::Activity::Upload, condition: true, nested_condition: true, seq: "[:condition, :update, :nested_condition, :notify, :finalize]", expected_ctx_variables: { "result.condition.default": true, "result.condition.nested": true }
    assert_invoke Song::Activity::Upload, condition: false, seq: "[:condition]", expected_ctx_variables: { "result.condition.default": false }
    assert_invoke Song::Activity::Upload, condition: true, nested_condition: false, seq: "[:condition, :update, :nested_condition, :finalize]", expected_ctx_variables: { "result.condition.default": true, "result.condition.nested": false }
  end
end

class IfTracingTest < Minitest::Spec
  class Song
    module Activity
      class Upload < Trailblazer::Activity::FastTrack
        class DecideWhatToDo
          def self.call(*); end
        end

        def self.my_condition_handler(*); end

        step If(:condition) {}
        step If(DecideWhatToDo) {}
        step If(method(:my_condition_handler)) {}
        step If(->(*) {}, id: "proc.my_condition_handler") {}

        #~meths
        include T.def_steps(:condition)
        #~meths end
      end
    end
  end

  it do
    [
      "If/condition",
      "If/IfTracingTest::Song::Activity::Upload::DecideWhatToDo",
      "If/method(:my_condition_handler)",
      "proc.my_condition_handler"
    ].each do |id|
      assert_equal Trailblazer::Developer::Introspect.find_path(Song::Activity::Upload, [id])[0].id, id
    end

    assert_equal trace(Song::Activity::Upload, { seq: [], condition: false })[0], <<~SEQ.chomp
      TOP
      |-- Start.default
      |-- If/condition
      |-- If/IfTracingTest::Song::Activity::Upload::DecideWhatToDo
      |-- If/method(:my_condition_handler)
      |-- proc.my_condition_handler
      `-- End.success
    SEQ
  end
end

class IfWithoutBlockTest < Minitest::Spec
  it do
    exception = assert_raises ArgumentError do
      class Song
        module Activity
          class Upload < Trailblazer::Activity::FastTrack
            step If(:condition)

            #~meths
            include T.def_steps(:condition)
            #~meths end
          end
        end
      end
    end
    assert_equal "If() requires a block", exception.message
  end
end
