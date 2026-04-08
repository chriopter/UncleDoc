require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows users settings by default" do
    get settings_url

    assert_response :success
    assert_select "h2", "People and access"
    assert_includes @response.body, "Users"
    assert_includes @response.body, "DB View"
    assert_not_includes @response.body, "/settings/healthkit"
  end

  test "legacy healthkit settings path falls back to users" do
    get settings_url(section: "healthkit")

    assert_response :success
    assert_select "h2", "People and access"
    assert_not_includes @response.body, "HealthKit Sync"
  end

  test "shows the users section" do
    get settings_url(section: "users")

    assert_response :success
    assert_select "h2", "People and access"
    assert_select "h3", text: "Add person and login"
  end

  test "shows first family member name in header when people exist" do
    get settings_url

    assert_response :success
    assert_includes @response.body, "MyString"
  end

  test "shows the full db section" do
    get settings_url(section: "db")

    assert_response :success
    assert_select "h2", "Raw database view"
    assert_includes @response.body, "/settings/db_table?table=entries"
    assert_includes @response.body, "entries"
  end

  test "db table uses infinite scroll and newest rows first" do
    person = people(:one)
    Entry.delete_all

    55.times do |index|
      Entry.create!(
        person: person,
        input: "db pagination #{index}",
        occurred_at: Time.current + index.minutes,
        facts: [],
        parseable_data: [],
        parse_status: "parsed"
      )
    end

    get settings_url(section: "db_table", table: "entries")

    assert_response :success
    assert_includes @response.body, "db pagination 54"
    assert_not_includes @response.body, "db pagination 0"
    assert_includes @response.body, "Loading more rows..."
    assert_includes @response.body, "page=2"

    get settings_url(section: "db_table", table: "entries", page: 2, format: :turbo_stream)

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_includes @response.body, "turbo-stream action=\"append\" target=\"db_table_rows\""
    assert_includes @response.body, "db pagination 0"
  end

  test "db table can delete an entry row" do
    person = people(:one)
    entry = Entry.create!(
      person: person,
      input: "delete me",
      occurred_at: Time.current,
      facts: [],
      parseable_data: [],
      parse_status: "parsed"
    )

    assert_difference("Entry.count", -1) do
      delete settings_db_row_url(table: "entries", row_id: entry.id, page: 1)
    end

    assert_redirected_to settings_path(section: "db_table", table: "entries", page: 1)
    follow_redirect!
    assert_includes @response.body, "Deleted row #{entry.id} from entries."
  end

  test "shows parser prompt in llm settings" do
    get settings_url(section: "llm")

    assert_response :success
    assert_includes @response.body, "Model configuration"
    assert_includes @response.body, "Parser system prompt"
    assert_includes @response.body, "Prompt and preview"
    assert_includes @response.body, "Affected user"
    assert_includes @response.body, "Workspace usage"
    assert_includes @response.body, "Price"
    assert_includes @response.body, "Global entry reparse"
    assert_not_includes @response.body, "href=\"/settings/llm_prompt\""
  end

  test "llm settings shows current unparsed entries" do
    person = Person.create!(name: "Unparsed Person", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(input: "stuck note", occurred_at: Time.zone.local(2026, 4, 8, 10, 0), parse_status: "failed", extracted_data: { "facts" => [], "document" => {}, "llm" => {} })
    person.entries.create!(input: "done note", occurred_at: Time.zone.local(2026, 4, 8, 11, 0), parse_status: "parsed", extracted_data: { "facts" => [ { "text" => "Done", "kind" => "note" } ], "document" => {}, "llm" => {} })

    get settings_url(section: "llm")

    assert_response :success
    assert_includes @response.body, "Unparsed entries"
    assert_includes @response.body, "Unparsed Person"
    assert_includes @response.body, "stuck note"
    assert_not_includes @response.body, "done note"
  end

  test "llm settings can kick off full reparse" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Reparse Person", birth_date: Date.new(2024, 1, 1))
    manual_entry = person.entries.create!(input: "reparse me", occurred_at: Time.zone.local(2026, 4, 8, 10, 0), parse_status: "parsed", extracted_data: { "facts" => [ { "text" => "Old", "kind" => "note" } ], "document" => {}, "llm" => { "status" => "structured" } })
    baby_entry = person.entries.create!(input: "Bottle 120ml", occurred_at: Time.zone.local(2026, 4, 8, 9, 0), source: Entry::SOURCES[:babywidget], parse_status: "parsed", extracted_data: { "facts" => [], "document" => {}, "llm" => {} })

    assert_enqueued_with(job: EntryReparseBatchJob) do
      post settings_llm_reparse_all_url
    end

    assert_redirected_to settings_path(section: "llm")
    assert_equal "pending", manual_entry.reload.parse_status
    assert_equal [], manual_entry.fact_objects
    assert_equal "parsed", baby_entry.reload.parse_status
    assert_equal "measurement", baby_entry.fact_objects.first["kind"]
  end

  test "global reparse does not enqueue chat context refresh jobs for every marked entry" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Quiet Reparse Person", birth_date: Date.new(2024, 1, 1))
    3.times do |index|
      person.entries.create!(input: "reparse #{index}", occurred_at: Time.zone.local(2026, 4, 8, 10, index), parse_status: "parsed", extracted_data: { "facts" => [ { "text" => "Old", "kind" => "note" } ], "document" => {}, "llm" => { "status" => "structured" } })
    end

    assert_no_enqueued_jobs only: ResearchChatContextRefreshJob do
      post settings_llm_reparse_all_url
    end
  end

  test "shows dedicated llm prompt page" do
    get settings_url(section: "llm_prompt")

    assert_response :success
    assert_includes @response.body, "Language model settings"
    assert_includes @response.body, "Parser system prompt"
    assert_includes @response.body, EntryDataParser.system_prompt.lines.first.strip
  end

  test "shows compact llm status when configured" do
    AppSetting.update_llm_settings(llm_provider: "ollama", llm_model: "llama3")

    get settings_url(section: "llm")

    assert_response :success
    assert_includes @response.body, "Model configuration"
    assert_includes @response.body, "llama3"
    assert_includes @response.body, "API key"
    assert_includes @response.body, "Edit"
  end

  test "llm models endpoint returns ollama models" do
    fake_response = Struct.new(:code, :body).new("200", { data: [ { id: "llama3" }, { id: "mistral" } ] }.to_json)

    http_singleton = Net::HTTP.singleton_class
    http_singleton.alias_method :__original_start_for_model_lookup_test, :start
    http_singleton.define_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| fake_response }
      block.call(http)
    end

    post settings_llm_models_url, params: { llm_provider: "ollama" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ "llama3", "mistral" ], body["models"]
    assert_equal "llama3", body["selected_model"]
  ensure
    http_singleton.alias_method :start, :__original_start_for_model_lookup_test if http_singleton.method_defined?(:__original_start_for_model_lookup_test)
    http_singleton.remove_method :__original_start_for_model_lookup_test if http_singleton.method_defined?(:__original_start_for_model_lookup_test)
  end

  test "updates preview using selected person" do
    selected_person = people(:two)

    get settings_url(section: "llm", preview_person_id: selected_person.id)

    assert_response :success
    assert_includes @response.body, "Showing live prompt data for #{selected_person.name}."
    assert_select "select[name='preview_person_id'] option[selected='selected'][value='#{selected_person.id}']", text: selected_person.name
  end

  test "preserves locale in settings" do
    get settings_url(locale: "de")

    assert_response :success
    assert_includes @response.body, "locale=de"
  end

  test "updates locale preference from URL params" do
    get settings_url(section: "users", locale: "de")

    assert_response :success
    assert_equal "de", UserPreference.current.locale

    # Reset
    UserPreference.update_locale("en")
  end

  test "updates date format preference via patch" do
    patch settings_url(section: "users", date_format: "compact")

    assert_redirected_to settings_path(section: "users")
    assert_equal "compact", UserPreference.current.date_format

    # Reset
    UserPreference.update_date_format("long")
  end
end
