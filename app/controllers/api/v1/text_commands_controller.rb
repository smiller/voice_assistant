module Api
  module V1
    class TextCommandsController < BaseController
      MAX_TRANSCRIPT_LENGTH = 1000

      def create
        transcript = params[:transcript]
        return head :bad_request if transcript.blank?
        return head :unprocessable_entity if transcript.length > MAX_TRANSCRIPT_LENGTH

        Rails.logger.info("[TextCommand] transcript: #{transcript.inspect}")
        command = LoopingReminderDispatcher.new.dispatch(transcript: transcript, user: @current_user)
        record  = VoiceCommand.create!(
          user:       @current_user,
          transcript: transcript,
          intent:     command[:intent],
          params:     command[:params],
          status:     "received"
        )
        audio_bytes = CommandResponder.new.respond(command: command, user: @current_user)
        record.update!(status: "processed")
        status = command[:intent] == :unknown ? 422 : 200
        send_data audio_bytes, type: "audio/mpeg", disposition: "inline", status: status
      end
    end
  end
end
