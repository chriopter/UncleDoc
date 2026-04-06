Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Global routes (no person context)
  root "dashboard#show"
  get "settings(/:section)", to: "settings#show", as: :settings
  patch "settings(/:section)", to: "settings#update"
  post "settings/llm_models", to: "settings#llm_models", as: :settings_llm_models
  get "ios/healthkit/people", to: "healthkit#people"
  get "ios/healthkit/status", to: "healthkit#status"
  post "ios/healthkit/sync", to: "healthkit#sync"
  match "ios/healthkit/reset", to: "healthkit#reset", via: [ :delete, :post ]
  resources :people, only: [ :create, :update, :destroy ] do
    resources :entries, only: [ :create, :show, :edit, :update, :destroy ] do
      patch :reparse, on: :member
      patch :toggle_todo, on: :member
    end
    resource :baby_feeding_timer, only: [ :create, :destroy ]
    resource :baby_sleep_timer, only: [ :create, :destroy ]
    post "baby_quick_actions/diaper", to: "baby_quick_actions#diaper", as: :baby_diaper_action
    post "baby_quick_actions/bottle", to: "baby_quick_actions#bottle", as: :baby_bottle_action
  end

  # Stateful person URLs
  scope "/:person_slug", constraints: { person_slug: /(?!settings|up|manifest|service-worker|people)[^\/]+/ } do
    root "dashboard#show", as: :person_root
    get "overview", to: "people#show", as: :person_overview
    get "trends", to: "people#trends", as: :person_trends
    get "calendar", to: "dashboard#calendar", as: :person_calendar
    get "baby", to: "people#baby", as: :person_baby
    get "log", to: "dashboard#log", as: :person_log
    get "files", to: "dashboard#files", as: :person_files
    post "log_summary", to: "dashboard#summarize_log", as: :person_log_summary
    post "chat", to: "dashboard#chat", as: :person_chat
  end
end
