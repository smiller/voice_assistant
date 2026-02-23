class ConfigController < ApplicationController
  before_action :require_authentication

  def show
    render json: {
      deepgram_key: ENV.fetch("DEEPGRAM_API_KEY"),
      voice_id: current_user.elevenlabs_voice_id
    }
  end
end
