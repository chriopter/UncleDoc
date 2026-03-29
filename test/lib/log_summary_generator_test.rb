require "test_helper"

class LogSummaryGeneratorTest < ActiveSupport::TestCase
  test "formats structured baby entries for llm prompts" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    entry = person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 29, 9, 0),
      note: "Baby fed",
      data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ]
    )

    formatted = LogSummaryGenerator.formatted_entries([ entry ])

    assert_includes formatted, "bottle_feeding 120 ml"
    assert_includes formatted, "Baby fed"
  end
end
