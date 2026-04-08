require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    sign_in_as(users(:two))
  end

  test "non admin cannot access settings" do
    get settings_path(section: :users)

    assert_redirected_to root_path
  end

  test "non admin cannot create people" do
    assert_no_difference("Person.count") do
      post people_path, params: { person: { name: "Blocked Person" } }
    end

    assert_redirected_to root_path
  end

  test "non admin cannot create people with login access" do
    assert_no_difference([ "Person.count", "User.count" ]) do
      post people_path, params: {
        person: {
          name: "Blocked Login",
          user_attributes: {
            email_address: "blocked@example.com",
            password: "very-secure-pass",
            password_confirmation: "very-secure-pass"
          }
        }
      }
    end

    assert_redirected_to root_path
  end
end
