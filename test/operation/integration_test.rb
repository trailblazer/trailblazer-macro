require "test_helper"

class IntegrationTest < Minitest::Spec
  Artist = Struct.new(:name)
  Song = Struct.new(:name, :artist_name)

  class SongCreate < Trailblazer::Operation
    step Model(Song, :new)
    # step ->(options, **) { options[:model] = Song.new }
    step :set_artist!
    step :save!

    def set_artist!(_options, model:, params:, **)
      model.artist_name = params[:artist][:name]
    end

    def save!(_options, params:, model:, **)
      model.name = params[:song][:name]
    end
  end

  class ArtistCreate < Trailblazer::Operation
    # step ->(options, **) { options[:model] = Artist.new }
    step Model(Artist, :new)
    step :save!

    def save!(_options, params:, model:, **)
      model.name = params[:artist][:name]
    end
  end

  class SongSpecialCreate < Trailblazer::Operation
    step Subprocess(ArtistCreate)
    step Subprocess(SongCreate)
  end

  it "create Artist and Song" do
    result = SongSpecialCreate.wtf?(
      params: {
        artist: {
          name: "My Artist"
        },
        song: {
          name: "My Song"
        }
      }
    )

    # this should return song
    assert_equal result[:model].name, "My Song"
    assert_equal result[:model].artist_name, "My Artist"
  end
end
