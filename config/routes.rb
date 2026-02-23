Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get  "login"   => "sessions#new",     as: :login
  post "session" => "sessions#create",  as: :session
  delete "session" => "sessions#destroy"

  resources :voice_commands, only: [ :index, :create ]
  resources :voice_alerts, only: [ :show ]
  get "config" => "config#show", as: :config

  root "voice_commands#index"
end
