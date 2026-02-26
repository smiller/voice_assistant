class VoiceAlertsController < AuthenticatedController
  def show
    key = "voice_alert_#{current_user.id}_#{params[:id]}"
    audio = Rails.cache.read(key)
    return head :not_found unless audio

    Rails.cache.delete(key)
    send_data audio, type: "audio/mpeg", disposition: "inline"
  end
end
