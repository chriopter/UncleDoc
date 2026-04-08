require "test_helper"

class BabyQuickActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)
  end

  test "creates diaper entry" do
    assert_difference("Entry.count", 1) do
      post person_baby_diaper_action_url(@person), params: { kind: "both" }
    end

    entry = Entry.order(:created_at).last
    assert_equal "Diaper: wet and solid", entry.input
    assert_equal [ "Diaper wet and solid" ], entry.facts
    assert_equal({ "type" => "diaper", "wet" => true, "solid" => true }, entry.parseable_data.first)
    assert_equal Entry::SOURCES[:babywidget], entry.source
  end

  test "creates bottle entry" do
    assert_difference("Entry.count", 1) do
      post person_baby_bottle_action_url(@person), params: { amount_ml: 120 }
    end

    entry = Entry.order(:created_at).last
    assert_equal "Bottle 120ml", entry.input
    assert_equal [ "Bottle feeding 120 ml" ], entry.facts
    assert_equal({ "type" => "bottle_feeding", "value" => 120, "unit" => "ml" }, entry.parseable_data.first)
    assert_equal Entry::SOURCES[:babywidget], entry.source
  end

  test "creates german localized diaper and bottle facts" do
    UserPreference.update_locale("de")

    post person_baby_diaper_action_url(@person), params: { kind: "wet" }
    diaper_entry = Entry.order(:created_at).last
    assert_equal [ "Windel nass" ], diaper_entry.facts

    post person_baby_bottle_action_url(@person), params: { amount_ml: 90 }
    bottle_entry = Entry.order(:created_at).last
    assert_equal [ "Flasche 90 ml" ], bottle_entry.facts
  ensure
    UserPreference.update_locale("en")
  end

  test "diaper responds with turbo stream" do
    post person_baby_diaper_action_url(@person, format: :turbo_stream), params: { kind: "wet" }

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, @response.media_type
  end
end
