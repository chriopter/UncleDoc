Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Non-person specific routes must come BEFORE the person_slug scope
  root "dashboard#show"
  get "settings(/:section)", to: "settings#show", as: :settings
  resources :people, only: [ :create, :destroy ] do
    resources :entries, only: [ :create, :destroy ]
  end

  # Stateful URLs with person context - exclude reserved paths
  scope "/:person_slug", constraints: { person_slug: /(?!settings|up|manifest|service-worker|people)[^\/]+/ } do
    root "dashboard#show", as: :person_root
    get "settings(/:section)", to: "settings#show", as: :person_settings
  end
end
