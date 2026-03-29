Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Global routes (no person context)
  root "dashboard#show"
  get "settings(/:section)", to: "settings#show", as: :settings
  patch "settings(/:section)", to: "settings#update"
  post "settings/llm_models", to: "settings#llm_models", as: :settings_llm_models
  resources :people, only: [ :create, :update, :destroy ] do
    resources :entries, only: [ :create, :destroy ]
    resource :baby_feeding_timer, only: [ :create, :destroy ]
    post "baby_quick_actions/diaper", to: "baby_quick_actions#diaper", as: :baby_diaper_action
    post "baby_quick_actions/bottle", to: "baby_quick_actions#bottle", as: :baby_bottle_action
  end

  # Stateful person URLs
  scope "/:person_slug", constraints: { person_slug: /(?!settings|up|manifest|service-worker|people)[^\/]+/ } do
    root "dashboard#show", as: :person_root
    get "overview", to: "people#show", as: :person_overview
    get "log", to: "dashboard#log", as: :person_log
    post "log_summary", to: "dashboard#summarize_log", as: :person_log_summary
  end
end
