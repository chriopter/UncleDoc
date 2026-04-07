require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows users settings by default" do
    Person.delete_all  # Clear fixtures for this test
    get settings_url

    assert_response :success
    assert_select "h2", "All family members"
    assert_includes @response.body, "Users"
    assert_includes @response.body, "DB View"
    assert_not_includes @response.body, "/settings/healthkit"
  end

  test "legacy healthkit settings path falls back to users" do
    get settings_url(section: "healthkit")

    assert_response :success
    assert_select "h2", "All family members"
    assert_not_includes @response.body, "HealthKit Sync"
  end

  test "shows the users section" do
    get settings_url(section: "users")

    assert_response :success
    assert_select "h2", "All family members"
    assert_select "p", text: "New User"
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
    LlmLog.create!(request_kind: "entry_parse", provider: "ollama", model: "llama3", endpoint: "http://localhost:11434/v1/chat/completions", request_payload: "{}", response_body: "[]", status_code: 200)

    get settings_url(section: "llm")

    assert_response :success
    assert_includes @response.body, "Workspace usage"
    assert_includes @response.body, "Total requests"
    assert_includes @response.body, "1"
  end

  test "shows dedicated llm prompt page" do
    get settings_url(section: "llm_prompt")

    assert_response :success
    assert_includes @response.body, "Parser system prompt"
    assert_includes @response.body, EntryDataParser.system_prompt.lines.first.strip
  end

  test "shows compact llm status when configured" do
    UserPreference.update_llm_settings(llm_provider: "ollama", llm_model: "llama3")

    get settings_url(section: "llm")

    assert_response :success
    assert_includes @response.body, "Model: llama3"
    assert_includes @response.body, "API key"
    assert_includes @response.body, "Edit"
  end

  test "shows llm log subnav and llm logs page" do
    LlmLog.create!(request_kind: "entry_parse", provider: "ollama", model: "llama3", endpoint: "http://localhost:11434/v1/chat/completions", request_payload: "{}", response_body: "[]", status_code: 200)

    get settings_url(section: "llm_logs")

    assert_response :success
    assert_includes @response.body, "Prompt"
    assert_includes @response.body, "Raw logs"
    assert_includes @response.body, "Raw LLM request log"
    assert_includes @response.body, "entry_parse"
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
