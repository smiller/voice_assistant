class ConfigController < AuthenticatedController
  def show
    render json: { voice_id: current_user.elevenlabs_voice_id }
  end
end
