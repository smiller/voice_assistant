module Api
  module V1
    class TextCommandsController < BaseController
      def create
        transcript = params[:transcript]
        return head :bad_request if transcript.blank?

        command = CommandParser.new.parse(transcript)
        audio_bytes = CommandResponder.new.respond(command: command, user: @current_user)
        send_data audio_bytes, type: "audio/mpeg", disposition: "inline"
      end
    end
  end
end
