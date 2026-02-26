class VoiceCommandsController < AuthenticatedController
  BLANK_TRANSCRIPT_MESSAGE = "Sorry, I didn't catch that, please try again"

  def index
    pending = current_user.reminders.pending.where("fire_at > ?", Time.current).includes(:user).order(:fire_at)
    @timers          = pending.timer
    @reminders       = pending.reminder
    @daily_reminders = pending.daily_reminder.sort_by { |r|
      local = r.fire_at.in_time_zone(current_user.timezone)
      [ local.hour, local.min ]
    }
    @looping_reminders = current_user.looping_reminders.includes(:command_aliases).order(:number)
  end

  def create
    audio = params[:audio]
    return head :bad_request unless audio
    return head :unprocessable_entity if audio.size < 1.kilobyte
    return head :unprocessable_entity if audio.size > 1.megabyte
    return head :unprocessable_entity unless audio.content_type&.start_with?("audio/")

    transcript = DeepgramClient.new.transcribe(audio: audio.read)
    if transcript.blank?
      audio_bytes = ElevenLabsClient.new.synthesize(
        text: BLANK_TRANSCRIPT_MESSAGE,
        voice_id: current_user.elevenlabs_voice_id
      )
      response.set_header("X-Status-Text", BLANK_TRANSCRIPT_MESSAGE)
      return send_data audio_bytes, type: "audio/mpeg", disposition: "inline"
    end

    Rails.logger.info("[VoiceCommand] transcript: #{transcript.inspect}")
    parsed = LoopingReminderDispatcher.new.dispatch(transcript: transcript, user: current_user)
    command = VoiceCommand.create!(
      user: current_user,
      transcript: transcript,
      intent: parsed[:intent],
      params: parsed[:params],
      status: "received"
    )
    audio_bytes = CommandResponder.new.respond(command: parsed, user: current_user)
    command.update!(status: "processed")

    if parsed[:intent] == :unknown
      response.set_header("X-Status-Text", CommandResponder::UNKNOWN_INTENT_MESSAGE)
    end
    send_data audio_bytes, type: "audio/mpeg", disposition: "inline"
  rescue DeepgramClient::Error
    head :unprocessable_entity
  end
end
