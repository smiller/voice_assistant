class SessionsController < ApplicationController
  def new
  end

  def create
    user = User.find_by(email: params[:email])
    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      save_location(user)
      redirect_to root_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def save_location(user)
    return if params[:lat].blank? || params[:lng].blank?
    return if user.lat.present? || user.lng.present?

    user.update!(lat: params[:lat], lng: params[:lng])
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path
  end
end
