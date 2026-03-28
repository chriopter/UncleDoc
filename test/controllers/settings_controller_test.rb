require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows profile settings by default" do
    get settings_url

    assert_response :success
    assert_select "h1", "Workspace settings"
    assert_select "h2", "Display preferences"
    assert_includes @response.body, "Profile settings"
    assert_includes @response.body, "Full DB view"
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
