require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows the log tab by default" do
    Person.delete_all
    get root_url

    assert_response :success
    assert_select "button", text: /Family/
    assert_select "a[aria-label='Settings']", 1
  end

  test "shows family member name when people exist" do
    get root_url

    assert_response :success
    # When fixtures are loaded, should show the first person's name
    assert_select "button", text: /MyString/
  end

  test "sets locale from user preferences" do
    # Set locale to German in preferences
    UserPreference.update_locale("de")

    get root_url

    assert_response :success
    # Verify German locale is active by checking Settings translation
    assert_select "a[aria-label='Einstellungen']", 1

    # Reset to English
    UserPreference.update_locale("en")
  end
end
