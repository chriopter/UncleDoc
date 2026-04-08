ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

ActiveJob::Base.queue_adapter = :test

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  setup do
    Current.reset
    sign_in_as(default_auth_user) unless skip_default_sign_in?
  end

  def default_auth_user
    User.find_by(email_address: "one@example.com") || users(:one)
  end

  def skip_default_sign_in?
    false
  end
end
