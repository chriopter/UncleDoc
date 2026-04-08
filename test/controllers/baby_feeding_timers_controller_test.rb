require "test_helper"

class BabyFeedingTimersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)
  end

  test "starts and stops feeding timer creating feeding entry" do
    travel_to Time.zone.local(2026, 3, 31, 12, 0, 0) do
      post person_baby_feeding_timer_url(@person), params: { side: "left" }
    end

    @person.reload
    assert_not_nil @person.baby_feeding_timer_started_at
    assert_equal "left", @person.baby_feeding_timer_side

    assert_difference("Entry.count", 1) do
      travel_to Time.zone.local(2026, 3, 31, 13, 35, 0) do
        delete person_baby_feeding_timer_url(@person)
      end
    end

    entry = Entry.order(:created_at).last
    @person.reload
    assert_nil @person.baby_feeding_timer_started_at
    assert_nil @person.baby_feeding_timer_side
    assert_equal "Breastfeeding Left, 95 minutes", entry.input
    assert_equal [ "Breast feeding Left 95 min" ], entry.facts
    assert_equal({ "type" => "breast_feeding", "value" => 95, "unit" => "min", "side" => "left" }, entry.parseable_data.first)
    assert_equal Entry::SOURCES[:babywidget], entry.source
  end

  test "feeding timer responds with turbo stream" do
    post person_baby_feeding_timer_url(@person, format: :turbo_stream), params: { side: "right" }

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, @response.media_type
  end
end
