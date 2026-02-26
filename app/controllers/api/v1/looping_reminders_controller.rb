module Api
  module V1
    class LoopingRemindersController < BaseController
      def index
        render json: @current_user.looping_reminders
                                  .includes(:command_aliases)
                                  .order(:number)
                                  .map { |lr|
          {
            id: lr.id,
            number: lr.number,
            message: lr.message,
            stop_phrase: lr.stop_phrase,
            interval_minutes: lr.interval_minutes,
            active: lr.active?,
            aliases: lr.command_aliases.map(&:phrase)
          }
        }
      end
    end
  end
end
