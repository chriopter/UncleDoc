require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows profile settings by default" do
    Person.delete_all  # Clear fixtures for this test
    get settings_url

    assert_response :success
    assert_select "h1", "Family"
    assert_select "h2", "Display preferences"
    assert_select "span", text: "Profile settings"
    assert_select "span", text: "Users"
    assert_select "span", text: "Full DB view"
  end

  test "shows the users section" do
    get settings_url(section: "users")

    assert_response :success
    assert_select "h2", "Family members"
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

  test "preserves locale and date format in settings" do
    get settings_url(locale: "de", date_format: "compact")

    assert_response :success
    assert_includes @response.body, "locale=de"
    assert_includes @response.body, "date_format=compact"
  end
end
