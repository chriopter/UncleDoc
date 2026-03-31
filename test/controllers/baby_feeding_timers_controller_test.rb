require "test_helper"

class BabyFeedingTimersControllerTest < ActionDispatch::IntegrationTest
  test "starts a feeding timer" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)

    post person_baby_feeding_timer_url(person), params: { side: "left" }

    assert_redirected_to root_url(person_slug: person.name, tab: "log")

    follow_redirect!

    assert_response :success
    assert_no_match(/feeding timer started|Still-Timer/, flash.to_hash.values.join(" "))
    assert_match(/Left/, @response.body)
    assert_match(/tap to stop|zum Stoppen tippen/, @response.body)
  end

  test "stops a feeding timer and creates an entry" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)

    travel_to Time.zone.local(2026, 3, 29, 10, 0, 0) do
      post person_baby_feeding_timer_url(person), params: { side: "left" }
    end

    travel_to Time.zone.local(2026, 3, 29, 10, 17, 0) do
      assert_difference("person.entries.count", 1) do
        delete person_baby_feeding_timer_url(person)
      end
    end

    entry = person.entries.order(:created_at).last

    assert_equal "breast_feeding", entry.parseable_data.first["type"]
    assert_equal 17, entry.parseable_data.first["value"]
    assert_equal "left", entry.parseable_data.first["side"]
    assert_equal [ "Breast feeding Left 17 min" ], entry.facts
    assert_match(/17/, entry.input)
  end

  test "creates german localized feeding facts" do
    UserPreference.update_locale("de")
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)

    travel_to Time.zone.local(2026, 3, 29, 10, 0, 0) do
      post person_baby_feeding_timer_url(person), params: { side: "left" }
    end

    travel_to Time.zone.local(2026, 3, 29, 10, 17, 0) do
      delete person_baby_feeding_timer_url(person)
    end

    entry = person.entries.order(:created_at).last
    assert_equal [ "Stillen Links 17 min" ], entry.facts
  ensure
    UserPreference.update_locale("en")
  end
end
