# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_08_153000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "llm_api_key"
    t.string "llm_model"
    t.string "llm_provider"
    t.datetime "updated_at", null: false
  end

  create_table "entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "facts", default: [], null: false
    t.text "input", null: false
    t.json "llm_response", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.string "parse_status", default: "parsed", null: false
    t.json "parseable_data", default: [], null: false
    t.integer "person_id", null: false
    t.string "source", default: "manual", null: false
    t.string "source_ref"
    t.boolean "todo_done", default: false, null: false
    t.datetime "todo_done_at"
    t.datetime "updated_at", null: false
    t.index ["person_id", "source", "source_ref"], name: "index_entries_on_person_source_and_source_ref", unique: true, where: "source_ref IS NOT NULL"
    t.index ["person_id"], name: "index_entries_on_person_id"
  end

  create_table "healthkit_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_id", null: false
    t.datetime "end_at"
    t.string "external_id", null: false
    t.json "payload", default: {}, null: false
    t.integer "person_id", null: false
    t.string "record_type", null: false
    t.string "source_name"
    t.datetime "start_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id", "external_id"], name: "index_healthkit_records_on_person_id_and_external_id", unique: true
    t.index ["person_id", "record_type", "start_at"], name: "idx_on_person_id_record_type_start_at_6a6717a011"
    t.index ["person_id"], name: "index_healthkit_records_on_person_id"
  end

  create_table "healthkit_syncs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "details", default: {}, null: false
    t.string "device_id", null: false
    t.text "last_error"
    t.datetime "last_successful_sync_at"
    t.datetime "last_synced_at"
    t.integer "person_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "synced_record_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["person_id", "device_id"], name: "index_healthkit_syncs_on_person_id_and_device_id", unique: true
    t.index ["person_id"], name: "index_healthkit_syncs_on_person_id"
  end

  create_table "llm_chats", force: :cascade do |t|
    t.datetime "context_refreshed_at"
    t.datetime "context_source_updated_at"
    t.datetime "created_at", null: false
    t.integer "llm_model_id"
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["llm_model_id"], name: "index_llm_chats_on_llm_model_id"
    t.index ["person_id"], name: "index_llm_chats_on_person_id", unique: true
  end

  create_table "llm_messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.boolean "hidden", default: false, null: false
    t.integer "input_tokens"
    t.integer "llm_chat_id", null: false
    t.integer "llm_model_id"
    t.integer "llm_tool_call_id"
    t.string "message_kind", default: "message", null: false
    t.integer "output_tokens"
    t.string "role", null: false
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.datetime "updated_at", null: false
    t.index ["llm_chat_id"], name: "index_llm_messages_on_llm_chat_id"
    t.index ["llm_model_id"], name: "index_llm_messages_on_llm_model_id"
    t.index ["llm_tool_call_id"], name: "index_llm_messages_on_llm_tool_call_id"
    t.index ["message_kind"], name: "index_llm_messages_on_message_kind"
    t.index ["role"], name: "index_llm_messages_on_role"
  end

  create_table "llm_models", force: :cascade do |t|
    t.json "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata", default: {}
    t.json "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_llm_models_on_family"
    t.index ["provider", "model_id"], name: "index_llm_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_llm_models_on_provider"
  end

  create_table "llm_tool_calls", force: :cascade do |t|
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.integer "llm_message_id", null: false
    t.string "name", null: false
    t.text "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["llm_message_id"], name: "index_llm_tool_calls_on_llm_message_id"
    t.index ["name"], name: "index_llm_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_llm_tool_calls_on_tool_call_id", unique: true
  end

  create_table "people", force: :cascade do |t|
    t.string "baby_feeding_timer_side"
    t.datetime "baby_feeding_timer_started_at"
    t.boolean "baby_mode"
    t.datetime "baby_sleep_timer_started_at"
    t.datetime "birth_date"
    t.datetime "created_at", null: false
    t.string "date_format"
    t.string "locale"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["uuid"], name: "index_people_on_uuid", unique: true
  end

  create_table "person_states", force: :cascade do |t|
    t.string "baby_feeding_timer_side"
    t.datetime "baby_feeding_timer_started_at"
    t.datetime "baby_sleep_timer_started_at"
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_person_states_on_person_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "date_format"
    t.string "locale"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "last_signed_in_at"
    t.text "native_app_token"
    t.string "native_app_token_digest"
    t.datetime "native_app_token_generated_at"
    t.datetime "native_app_token_last_used_at"
    t.string "password_digest"
    t.datetime "password_set_at"
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["native_app_token_digest"], name: "index_users_on_native_app_token_digest", unique: true
    t.index ["person_id"], name: "index_users_on_person_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "entries", "people", on_delete: :cascade
  add_foreign_key "healthkit_records", "people"
  add_foreign_key "healthkit_syncs", "people"
  add_foreign_key "llm_chats", "llm_models"
  add_foreign_key "llm_chats", "people"
  add_foreign_key "llm_messages", "llm_chats"
  add_foreign_key "llm_messages", "llm_models"
  add_foreign_key "llm_messages", "llm_tool_calls"
  add_foreign_key "llm_tool_calls", "llm_messages"
  add_foreign_key "person_states", "people"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "people"
end
