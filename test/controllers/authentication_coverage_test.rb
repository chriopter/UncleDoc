require "test_helper"

class AuthenticationCoverageTest < ActionDispatch::IntegrationTest
  def skip_default_sign_in?
    true
  end

  test "all protected endpoints redirect unauthenticated requests to login" do
    person = Person.create!(name: "Coverage Person", birth_date: Date.new(2024, 1, 1), baby_mode: true)
    entry = person.entries.create!(input: "Coverage entry", occurred_at: Time.current, facts: [], parseable_data: [], parse_status: "parsed")

    requests = {
      "root" => -> { get root_path },
      "manifest" => -> { get pwa_manifest_path(format: :json) },
      "service worker" => -> { get pwa_service_worker_path(format: :js) },
      "settings" => -> { get settings_path(section: :users) },
      "settings update" => -> { patch settings_path(section: :users), params: { date_format: "compact" } },
      "settings delete row" => -> { delete settings_db_row_path(table: "entries", row_id: entry.id) },
      "settings llm models" => -> { post settings_llm_models_path, params: { llm_provider: "ollama" } },
      "settings llm test" => -> { post settings_llm_test_path },
      "settings llm reparse all" => -> { post settings_llm_reparse_all_path },
      "settings prompt preview" => -> { get settings_prompt_preview_path(kind: "summary", person_id: person.id) },
      "healthkit people" => -> { get "/ios/healthkit/people" },
      "healthkit status" => -> { get "/ios/healthkit/status", params: { person_uuid: person.uuid } },
      "healthkit sync" => -> { post "/ios/healthkit/sync", params: { person_uuid: person.uuid, device_id: "device-a" } },
      "healthkit reset" => -> { delete "/ios/healthkit/reset", params: { person_uuid: person.uuid } },
      "create person" => -> { post people_path, params: { person: { name: "New Person" } } },
      "update person" => -> { patch person_path(person), params: { person: { name: "Updated" } } },
      "destroy person" => -> { delete person_path(person) },
      "create entry" => -> { post person_entries_path(person), params: { entry: { input: "Note", occurred_at: Time.current.iso8601 } } },
      "show entry" => -> { get person_entry_path(person, entry) },
      "edit entry" => -> { get edit_person_entry_path(person, entry) },
      "update entry" => -> { patch person_entry_path(person, entry), params: { entry: { input: "Updated", occurred_at: Time.current.iso8601 } } },
      "destroy entry" => -> { delete person_entry_path(person, entry) },
      "reparse entry" => -> { patch reparse_person_entry_path(person, entry) },
      "toggle todo entry" => -> { patch toggle_todo_person_entry_path(person, entry) },
      "feeding timer start" => -> { post person_baby_feeding_timer_path(person), params: { side: "left" } },
      "feeding timer stop" => -> { delete person_baby_feeding_timer_path(person) },
      "sleep timer start" => -> { post person_baby_sleep_timer_path(person) },
      "sleep timer stop" => -> { delete person_baby_sleep_timer_path(person) },
      "baby diaper action" => -> { post person_baby_diaper_action_path(person), params: { kind: "wet" } },
      "baby bottle action" => -> { post person_baby_bottle_action_path(person), params: { amount_ml: 120 } },
      "person root" => -> { get person_root_path(person_slug: person.name) },
      "person baby" => -> { get person_baby_path(person_slug: person.name) },
      "person log" => -> { get person_log_path(person_slug: person.name) },
      "person files" => -> { get person_files_path(person_slug: person.name) },
      "person file" => -> { get person_file_path(person_slug: person.name, entry_id: entry.id) },
      "person file content" => -> { get person_file_content_path(person_slug: person.name, entry_id: entry.id) },
      "person healthkit sync summaries" => -> { post person_healthkit_sync_summaries_path(person_slug: person.name) },
      "person healthkit reparse" => -> { post person_healthkit_reparse_path(person_slug: person.name) },
      "person healthkit records" => -> { get person_healthkit_records_path(person_slug: person.name) },
      "person log summary" => -> { post person_log_summary_path(person_slug: person.name) },
      "person chat" => -> { post person_chat_path(person_slug: person.name), params: { message: "Hi" } },
      "logout" => -> { delete session_path }
    }

    requests.each do |name, request|
      request.call
      assert_redirected_to new_session_path, "Expected #{name} to redirect to login"
    end
  end

  test "health check stays public" do
    get rails_health_check_path

    assert_response :success
  end

  test "root redirects to first run when no users exist" do
    User.delete_all
    Session.delete_all
    Person.delete_all

    get root_path

    assert_redirected_to first_run_path
  end

  test "root redirects to login when people exist without configured passwords" do
    User.delete_all
    Session.delete_all
    Person.delete_all

    person = Person.create!(name: "Existing Person")
    User.create!(person: person, email_address: "person-#{person.id}@uncledoc.invalid")

    get root_path

    assert_redirected_to new_session_path
  end
end
