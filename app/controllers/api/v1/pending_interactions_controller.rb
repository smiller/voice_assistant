module Api
  module V1
    class PendingInteractionsController < BaseController
      def show
        pending = PendingInteraction.for(@current_user)
        if pending
          render json: { kind: pending.kind, context: pending.context, expires_at: pending.expires_at }
        else
          head :no_content
        end
      end
    end
  end
end
