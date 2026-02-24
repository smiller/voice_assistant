class VoiceCommandsController < AuthenticatedController
  def index
  end

  def create
    audio = params[:audio]
    return head :bad_request unless audio

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
    audio_bytes = CommandResponder.new.respond(transcript: transcript, user: current_user)
    command.update!(status: "processed")

    send_data audio_bytes, type: "audio/mpeg", disposition: "inline"
  end
end
