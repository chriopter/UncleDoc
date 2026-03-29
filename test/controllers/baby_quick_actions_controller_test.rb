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
    assert_equal "Diaper: wet and solid", entry.note
    assert_equal({ "type" => "diaper", "wet" => true, "solid" => true }, entry.data.first)
  end

  test "creates bottle entry" do
    assert_difference("Entry.count", 1) do
      post person_baby_bottle_action_url(@person), params: { amount_ml: 120 }
    end

    entry = Entry.order(:created_at).last
    assert_equal "Bottle 120ml", entry.note
    assert_equal({ "type" => "bottle_feeding", "value" => 120, "unit" => "ml" }, entry.data.first)
  end
end
