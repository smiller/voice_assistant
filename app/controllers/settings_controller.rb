class SettingsController < ApplicationController
  before_action :require_authentication

  def edit; end

  def update
    if current_user.update(user_params)
      redirect_to root_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:elevenlabs_voice_id, :lat, :lng, :timezone)
  end
end
