require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows the log tab by default" do
    get root_url

    assert_response :success
    assert_select "h1", "Family Health Tracker"
    assert_select "a", text: "Log"
  end

  test "shows the db tab" do
    get root_url(tab: "db")

    assert_response :success
    assert_select "h2", "Raw database view"
  end
end
