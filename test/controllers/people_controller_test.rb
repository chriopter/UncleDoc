require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  test "creates a person" do
    assert_difference("Person.count", 1) do
      assert_difference("User.count", 1) do
        post people_url, params: {
          person: {
            name: "Mila",
            birth_date: "2024-03-10",
            user_attributes: {
              email_address: "mila@example.com",
              password: "very-secure-pass",
              password_confirmation: "very-secure-pass",
              admin: "0"
            }
          }
        }
      end
    end

    assert_redirected_to root_url(person_slug: "Mila", tab: "log")
    assert_equal "mila@example.com", Person.find_by!(name: "Mila").user.email_address
  end

  test "does not create invalid person" do
    assert_no_difference("Person.count") do
      assert_no_difference("User.count") do
        post people_url, params: {
          person: {
            name: "",
            birth_date: "2024-03-10",
            user_attributes: { email_address: "bad@example.com" }
          }
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "deletes a person" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10))
    person.entries.create!(input: "Bottle 120ml", occurred_at: Time.current)

    assert_difference("Person.count", -1) do
      assert_difference("Entry.count", -1) do
        delete person_url(person)
      end
    end

    # After deleting, should redirect to root without a person context
    # (or to another family member if one exists)
    assert_redirected_to %r{\A#{root_url}(\?.*)?\z}
  end

  test "deletes a person as turbo stream" do
    person = Person.create!(name: "Turbo Mila", birth_date: Date.new(2024, 3, 10))
    person.entries.create!(input: "Bottle 120ml", occurred_at: Time.current)

    assert_difference("Person.count", -1) do
      assert_difference("Entry.count", -1) do
        delete person_url(person), as: :turbo_stream
      end
    end

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_includes @response.body, "people_list"
  end

  test "settings users page renders delete links outside nested forms" do
    person = Person.create!(name: "Delete UI", birth_date: Date.new(2024, 3, 10))

    get settings_url(section: "users")

    assert_response :success
    assert_select "a[data-turbo-method='delete'][href='#{person_path(person)}']", 1
  end

  test "updates a person including datetime birth date, baby mode, and personal display settings" do
    person = Person.create!(name: "Mila", birth_date: Time.zone.local(2024, 3, 10, 12, 0))
    person.create_user!(email_address: "mila@example.com", password: "very-secure-pass", password_confirmation: "very-secure-pass")

    patch person_url(person), params: {
      person: {
        name: "Mila Rose",
        birth_date: "2024-03-11T08:30",
        baby_mode: "1",
        user_attributes: {
          id: person.user.id,
          email_address: "mila.rose@example.com",
          password: "even-more-secure",
          password_confirmation: "even-more-secure",
          admin: "1"
        }
      }
    }

    assert_redirected_to %r{(settings/users|/Mila%20Rose)}
    person.reload
    assert_equal "Mila Rose", person.name
    assert_equal Time.zone.parse("2024-03-11T08:30"), person.birth_date
    assert person.baby_mode?
    assert_equal "mila.rose@example.com", person.user.email_address
    assert person.user.admin?
  end

end
