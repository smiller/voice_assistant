Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get  "login"   => "sessions#new",     as: :login
  post "session" => "sessions#create",  as: :session
  delete "session" => "sessions#destroy"

  resources :voice_commands, only: [ :index, :create ]
  resources :voice_alerts, only: [ :show ]
  resource :settings, only: [ :edit, :update ]
  get "config" => "config#show", as: :config

  namespace :api do
    namespace :v1 do
      resources :text_commands, only: [ :create ]
      resources :looping_reminders, only: [ :index ]
    end
  end

  root "voice_commands#index"
end
