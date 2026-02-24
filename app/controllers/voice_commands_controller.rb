class VoiceCommandsController < AuthenticatedController
  def index
  end

  def create
    audio = params[:audio]
    return head :bad_request unless audio
    return head :unprocessable_entity if audio.size < 1.kilobyte
    return head :unprocessable_entity if audio.size > 1.megabyte
    return head :unprocessable_entity unless audio.content_type&.start_with?("audio/")

    transcript = DeepgramClient.new.transcribe(audio: audio.read)
    return head :bad_request if transcript.blank?

    parsed = CommandParser.new.parse(transcript)
    command = VoiceCommand.create!(
      user: current_user,
      transcript: transcript,
      intent: parsed[:intent],
      params: parsed[:params],
      status: "received"
    )
    audio_bytes = CommandResponder.new.respond(command: parsed, user: current_user)
    command.update!(status: "processed")

    send_data audio_bytes, type: "audio/mpeg", disposition: "inline"
  rescue DeepgramClient::Error
    head :unprocessable_entity
  end
end
