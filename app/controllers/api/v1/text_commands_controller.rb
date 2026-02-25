module Api
  module V1
    class TextCommandsController < BaseController
      def create
        transcript = params[:transcript]
        return head :bad_request if transcript.blank?

        command     = CommandParser.new.parse(transcript)
        audio_bytes = CommandResponder.new.respond(command: command, user: @current_user)
        status      = command[:intent] == :unknown ? 422 : 200
        send_data audio_bytes, type: "audio/mpeg", disposition: "inline", status: status
      end
    end
  end
end
