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

  test "updates a person including datetime birth date and baby mode" do
    person = Person.create!(name: "Mila", birth_date: Time.zone.local(2024, 3, 10, 12, 0))

    patch person_url(person), params: {
      person: {
        name: "Mila Rose",
        birth_date: "2024-03-11T08:30",
        baby_mode: "1"
      }
    }

    assert_redirected_to %r{(settings/users|/Mila%20Rose/overview)}
    person.reload
    assert_equal "Mila Rose", person.name
    assert_equal Time.zone.parse("2024-03-11T08:30"), person.birth_date
    assert person.baby_mode?
  end

  test "shows newborn age in days on overview" do
    person = Person.create!(name: "Baby", birth_date: Time.zone.now - 5.days)

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "5 days old"
  end
end
