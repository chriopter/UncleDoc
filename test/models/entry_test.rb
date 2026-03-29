require "test_helper"

class EntryTest < ActiveSupport::TestCase
  test "defaults data to empty array" do
    entry = Entry.new(note: "Plain note")

    assert_equal [], entry.data
    assert entry.occurred_at.present?
  end

  test "filters data by type" do
    person = Person.create!(name: "Mila", birth_date: Date.new(2024, 3, 10), baby_mode: true)
    feeding = person.entries.create!(
      note: "Bottle 120ml",
      occurred_at: Time.current,
      data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ]
    )
    person.entries.create!(
      note: "Diaper wet",
      occurred_at: Time.current,
      data: [ { "type" => "diaper", "wet" => true, "solid" => false } ]
    )

    assert_equal [ feeding ], Entry.by_data_type("bottle_feeding")
    assert_equal 1, feeding.data_of_type("bottle_feeding").size
  end
end
