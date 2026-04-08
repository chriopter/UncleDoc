require "test_helper"

class NativeAppAuthenticationTest < ActionDispatch::IntegrationTest
  def skip_default_sign_in?
    true
  end

  test "native app responses expose the authenticated app token in meta tags" do
    sign_in_as(users(:one))

    get root_url, headers: { "User-Agent" => "UncleDoc iOS" }

    assert_response :success
    assert_select "meta[name='uncledoc-native-app-token']", 1
    assert_select "meta[name='uncledoc-native-app-email'][content='one@example.com']", 1
    assert users(:one).reload.native_app_token_digest.present?
  end

  test "healthkit endpoints accept bearer token auth without a web session" do
    person = people(:one)
    token = users(:one).ensure_native_app_token!

    get "/ios/healthkit/people", headers: {
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json",
      "User-Agent" => "UncleDoc iOS"
    }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.fetch("people").map { |entry| entry.fetch("uuid") }, person.uuid
  end

  test "healthkit endpoints reject invalid bearer tokens" do
    get "/ios/healthkit/people", headers: {
      "Authorization" => "Bearer invalid-token",
      "Accept" => "application/json",
      "User-Agent" => "UncleDoc iOS"
    }

    assert_response :unauthorized
    assert_includes response.parsed_body.fetch("error"), "sign in"
  end
end
