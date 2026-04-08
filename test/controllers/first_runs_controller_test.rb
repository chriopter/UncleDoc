require "test_helper"

class FirstRunsControllerTest < ActionDispatch::IntegrationTest
  def skip_default_sign_in?
    true
  end

  setup do
    User.delete_all
    Session.delete_all
    Person.delete_all
  end

  test "shows first run when no users exist" do
    get first_run_path

    assert_response :success
    assert_includes @response.body, "Create the first administrator"
  end

  test "creates first admin account and linked person" do
    assert_difference([ "User.count", "Person.count" ], 1) do
      post first_run_path, params: {
        setup: {
          person_name: "Admin Person",
          birth_date: "2024-01-01T10:00",
          email_address: "admin@example.com",
          password: "very-secure-pass",
          password_confirmation: "very-secure-pass"
        }
      }
    end

    user = User.find_by!(email_address: "admin@example.com")
    assert user.admin?
    assert_equal "Admin Person", user.person.name
    assert_redirected_to root_path
  end

  test "redirects first run to login once users exist" do
    User.create!(person: Person.create!(name: "Admin Person"), email_address: "admin@example.com", password: "very-secure-pass", password_confirmation: "very-secure-pass", admin: true)

    get first_run_path

    assert_redirected_to new_session_path
  end

  test "redirects first run to login when people already exist" do
    Person.create!(name: "Existing Person")

    get first_run_path

    assert_redirected_to new_session_path
  end
end
