require "test_helper"

class BabySleepTimersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)
  end

  test "starts and stops sleep timer creating sleep entry" do
    travel_to Time.zone.local(2026, 3, 31, 12, 0, 0) do
      post person_baby_sleep_timer_url(@person)
    end

    assert_not_nil @person.reload.baby_sleep_timer_started_at

    assert_difference("Entry.count", 1) do
      travel_to Time.zone.local(2026, 3, 31, 13, 35, 0) do
        delete person_baby_sleep_timer_url(@person)
      end
    end

    entry = Entry.order(:created_at).last
    assert_nil @person.reload.baby_sleep_timer_started_at
    assert_equal "Sleep 95 min", entry.input
    assert_equal [ "Sleep 95 min" ], entry.facts
    assert_equal({ "type" => "sleep", "value" => 95, "unit" => "min" }, entry.parseable_data.first)
    assert_equal Entry::SOURCES[:babywidget], entry.source
  end

  test "sleep timer responds with turbo stream" do
    post person_baby_sleep_timer_url(@person, format: :turbo_stream)

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, @response.media_type
  end
end
