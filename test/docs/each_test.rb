require "test_helper"

class DocsEachTest < Minitest::Spec
  #:params
  array = [1, 2, 3]
  #:params end

  #:activity
  class Multiplication < Trailblazer::Activity::Railway
    step :init_result_array
    step Each(source: :array, target: :element) {
      step :multiplication
    }

    def init_result_array(ctx, params, **)
      ctx[:result_array] = []
      ctx[:array] = params[:array]
      true
    end

    def multiplication(ctx, params, **)
      ctx[:result_array] << ctx[:element] * 2
      true
    end
  end
  #:activity end

  it do
    signal, (ctx, _) = Multiplication.(array: array)
    signal.to_h[:semantic].must_equal :success
    ctx[:result_array].must_equal [2,4,6]
  end

  #:activity
  class FailingMultiplication < Trailblazer::Activity::Railway
    step :init_result_array
    step Each(source: :array, target: :element) {
      step :multiplication
    }

    def init_result_array(ctx, params, **)
      ctx[:result_array] = []
      ctx[:array] = params[:array]
      true
    end

    def multiplication(ctx, params, **)
      return if ctx[:element] == 2
      ctx[:result_array] << ctx[:element] * 2
      true
    end
  end
  #:activity end

  it do
    signal, (ctx, _) = FailingMultiplication.(array: array)
    signal.to_h[:semantic].must_equal :failure
    ctx[:result_array].must_equal [2]
  end
  
end
