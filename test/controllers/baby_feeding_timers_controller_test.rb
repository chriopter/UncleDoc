require "test_helper"

class BabyFeedingTimersControllerTest < ActionDispatch::IntegrationTest
  test "starts a feeding timer" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)

    post person_baby_feeding_timer_url(person)

    assert_redirected_to root_url(person_slug: person.name, tab: "log")

    follow_redirect!

    assert_response :success
    assert_select "form[action='#{person_baby_feeding_timer_path(person)}'] button", text: /Stop and save|Stoppen und speichern/
  end

  test "stops a feeding timer and creates an entry" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)

    travel_to Time.zone.local(2026, 3, 29, 10, 0, 0) do
      post person_baby_feeding_timer_url(person)
    end

    travel_to Time.zone.local(2026, 3, 29, 10, 17, 0) do
      assert_difference("person.entries.count", 1) do
        delete person_baby_feeding_timer_url(person)
      end
    end

    entry = person.entries.order(:created_at).last

    assert_equal "baby_feeding", entry.entry_type
    assert_equal 17, entry.metadata["duration_minutes"]
    assert_match(/17/, entry.note)
  end
end
