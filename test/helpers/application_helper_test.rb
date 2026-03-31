require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "baby activity series counts imported feeding and diaper text notes" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2025, 1, 1), baby_mode: true)

    travel_to Time.zone.local(2026, 3, 31, 12, 0, 0) do
      person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 8, 15), input: "Windel: nass; Trinken gut", facts: [ "Trinken gut", "Windel nass" ], parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => false } ])
      person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 10, 15), input: "Trinken gut", facts: [ "Trinken gut" ], parseable_data: [])
      person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 12, 0), input: "Flasche 120ml", facts: [ "Flasche 120 ml" ], parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ])

      feeding_counts = baby_activity_series(person, :feeding).index_by { |point| point[:date] }
      diaper_counts = baby_activity_series(person, :diaper).index_by { |point| point[:date] }

      assert_equal 2, feeding_counts[Date.new(2026, 3, 28)][:count]
      assert_equal 1, diaper_counts[Date.new(2026, 3, 28)][:count]
      assert_equal 1, feeding_counts[Date.new(2026, 3, 30)][:count]
    end
  end
end
