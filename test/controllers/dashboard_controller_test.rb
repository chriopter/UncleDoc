require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows the log tab by default" do
    get root_url

    assert_response :success
    assert_select "h1", "Family Health Tracker"
    assert_select "span", text: "Timeline"
    assert_select "a[aria-label='Settings']", 1
  end

  test "keeps the selected locale in the interface" do
    get root_url(locale: "de")

    assert_response :success
    assert_select "a[href*='locale=de']", minimum: 1
  end
end
