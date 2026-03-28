require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows the log tab by default" do
    Person.delete_all
    get root_url

    assert_response :success
    assert_select "button", text: /Family/
    assert_select "span", text: "Timeline"
    assert_select "a[aria-label='Settings']", 1
  end

  test "shows family member name when people exist" do
    get root_url

    assert_response :success
    # When fixtures are loaded, should show the first person's name
    assert_select "button", text: /MyString/
  end

  test "keeps the selected locale in the interface" do
    get root_url(locale: "de")

    assert_response :success
    assert_select "a[href*='locale=de']", minimum: 1
  end
end
