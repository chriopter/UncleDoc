require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  test "creates a person" do
    assert_difference("Person.count", 1) do
      post people_url, params: { person: { name: "Mila", birth_date: "2024-03-10" } }
    end

    assert_redirected_to root_url(person_slug: "Mila", tab: "log")
  end

  test "does not create invalid person" do
    assert_no_difference("Person.count") do
      post people_url, params: { person: { name: "", birth_date: "2024-03-10" } }
    end

    assert_response :unprocessable_entity
  end

  test "deletes a person" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10))

    assert_difference("Person.count", -1) do
      delete person_url(person)
    end

    # After deleting, should redirect to root without a person context
    # (or to another family member if one exists)
    assert_redirected_to %r{\A#{root_url}(\?.*)?\z}
  end
end
