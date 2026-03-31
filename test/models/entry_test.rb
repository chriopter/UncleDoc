require "test_helper"

class EntryTest < ActiveSupport::TestCase
  test "defaults parseable_data to empty array" do
    entry = Entry.new(input: "Plain input")

    assert_equal [], entry.parseable_data
    assert_equal [], entry.facts
    assert entry.occurred_at.present?
  end

  test "filters parseable_data by type" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)
    feeding = person.entries.create!(
      input: "Bottle 120ml",
      occurred_at: Time.current,
      parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ]
    )
    person.entries.create!(
      input: "Diaper wet",
      occurred_at: Time.current,
      parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => false } ]
    )

    assert_equal [ feeding ], Entry.by_parseable_data_type("bottle_feeding")
    assert_equal 1, feeding.parseable_data_of_type("bottle_feeding").size
  end

  test "fact summary joins facts" do
    entry = Entry.new(input: "raw", facts: [ "Bottle feeding 120 ml", "Diaper wet" ])

    assert_equal "Bottle feeding 120 ml. Diaper wet", entry.fact_summary
  end
end
