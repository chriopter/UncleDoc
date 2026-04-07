require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows profile settings by default" do
    Person.delete_all  # Clear fixtures for this test
    get settings_url

    assert_response :success
    assert_select "h2", "Display preferences"
    assert_select "span", text: "Profile"
    assert_select "span", text: "Members"
    assert_includes @response.body, "DB View"
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
    get settings_url(section: "profile", locale: "de")

    assert_response :success
    assert_equal "de", UserPreference.current.locale

    # Reset
    UserPreference.update_locale("en")
  end

  test "updates date format preference via patch" do
    patch settings_url(section: "profile", date_format: "compact")

    assert_redirected_to settings_path(section: "profile")
    assert_equal "compact", UserPreference.current.date_format

    # Reset
    UserPreference.update_date_format("long")
  end
end
