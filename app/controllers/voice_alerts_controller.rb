class VoiceAlertsController < ApplicationController
  def show
    audio = Rails.cache.read("reminder_audio_#{params[:id]}")
    return head :not_found unless audio

    Rails.cache.delete("reminder_audio_#{params[:id]}")
    send_data audio, type: "audio/mpeg", disposition: "inline"
  end
end
