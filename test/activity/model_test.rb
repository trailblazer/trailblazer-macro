require_relative "test_helper"

# Test that Railway can use Model() without any operation logic.
# This is a smoke test, not a unit test.
class ActivityModelTest < Minitest::Spec
  # TODO: share fixtures.
  Song = Struct.new(:id, :title) do
    def self.find_by(args)
      key, value = args.flatten
      return nil if value.nil?
      return new(value) if key == :id
      new(2, value) if key == :title
    end

    def self.[](id)
      id.nil? ? nil : new(id+99)
    end
  end

  module Song::Activity
    class Update < Trailblazer::Activity::Railway
      step Model(Song, :find_by)
      step :validate
      step :save
      #~meths
      include T.def_steps(:validate, :save)
      #~meths end
    end
  end

  it "finds the model" do
    lib_ctx, _ = assert_run Song::Activity::Update, target_ctx: {params: {id: 1}, seq: []}, seq: [:validate, :save], terminus: :success
    assert_equal lib_ctx[:target_ctx][:model], Song.new(1)
  end

  it "fails with unknown ID" do
    lib_ctx, _ = assert_run Song::Activity::Update, target_ctx: {params: {id: nil}, seq: []}, seq: [], terminus: :failure
    assert_nil lib_ctx[:target_ctx][:model]
  end
end
