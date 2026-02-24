module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_from_token!

      private

      def authenticate_from_token!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        @current_user = User.find_by(api_token: token)
        head :unauthorized unless @current_user
      end
    end
  end
end
