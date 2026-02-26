module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_from_token!

      private

      def authenticate_from_token!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        @current_user = token && User.find_by_api_token(token)
        head :unauthorized unless @current_user
      end
    end
  end
end
