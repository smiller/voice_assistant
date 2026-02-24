class ConfigController < ApplicationController
  before_action :require_authentication

  def show
    render json: { voice_id: current_user.elevenlabs_voice_id }
  end
end
