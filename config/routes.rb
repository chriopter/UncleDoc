Rails.application.routes.draw do
  resource :first_run, only: %i[show create]
  resource :session
  get "up" => "health#show", as: :rails_health_check
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker

  # Global routes (no person context)
  root "dashboard#show"
  get "settings(/:section)", to: "settings#show", as: :settings
  patch "settings(/:section)", to: "settings#update"
  delete "settings/db_row", to: "settings#destroy_db_row", as: :settings_db_row
  post "settings/llm_models", to: "settings#llm_models", as: :settings_llm_models
  post "settings/llm_test", to: "settings#llm_test", as: :settings_llm_test
  post "settings/llm_reparse_all", to: "settings#llm_reparse_all", as: :settings_llm_reparse_all
  get "settings/prompt_preview/:kind/:person_id", to: "settings#prompt_preview", as: :settings_prompt_preview
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
    get "calendar", to: "dashboard#calendar", as: :person_calendar
    get "baby", to: "people#baby", as: :person_baby
    get "log", to: "dashboard#log", as: :person_log
    get "research", to: "dashboard#research", as: :person_research
    get "files", to: "dashboard#files", as: :person_files
    post "files/reparse", to: "dashboard#queue_file_reparse", as: :person_files_reparse
    get "files/:entry_id", to: "dashboard#file", as: :person_file
    get "files/:entry_id/content", to: "dashboard#file_content", as: :person_file_content
    get "files/:entry_id/thumbnail", to: "dashboard#file_thumbnail", as: :person_file_thumbnail
    get "healthkit", to: "dashboard#healthkit", as: :person_healthkit
    post "healthkit/sync_summaries", to: "dashboard#queue_healthkit_summary_sync", as: :person_healthkit_sync_summaries
    post "healthkit/reparse", to: "dashboard#queue_healthkit_reparse", as: :person_healthkit_reparse
    get "healthkit/records", to: "dashboard#healthkit_records_page", as: :person_healthkit_records
    post "log_summary", to: "dashboard#summarize_log", as: :person_log_summary
    post "chat", to: "research_messages#create", as: :person_chat
  end
end
