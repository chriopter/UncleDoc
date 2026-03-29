require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows profile settings by default" do
    Person.delete_all  # Clear fixtures for this test
    get settings_url

    assert_response :success
    assert_select "h1", "Family"
    assert_select "span", text: "Profile settings"
    assert_select "span", text: "Users"
    assert_select "span", text: "Full DB view"
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
    # With fixtures loaded, should show first person's name
    assert_select "h1", "MyString"
  end

  test "shows the full db section" do
    get settings_url(section: "db")

    assert_response :success
    assert_select "h2", "Raw database view"
  end

  test "shows parser prompt in llm settings" do
    get settings_url(section: "llm")

    assert_response :success
    assert_includes @response.body, EntryDataParser.system_prompt.lines.first.strip
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
