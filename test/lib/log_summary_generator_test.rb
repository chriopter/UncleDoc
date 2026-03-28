require "test_helper"

class LogSummaryGeneratorTest < ActiveSupport::TestCase
  test "formats structured baby entries for llm prompts" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    entry = person.entries.create!(
      date: Date.new(2026, 3, 29),
      note: "Baby fed",
      entry_type: "baby_feeding",
      metadata: { "method" => "bottle", "amount_ml" => "120" }
    )

    formatted = LogSummaryGenerator.formatted_entries([ entry ])

    assert_includes formatted, "Feeding"
    assert_includes formatted, "Method: Bottle"
    assert_includes formatted, "Amount (ml): 120"
    assert_includes formatted, "Baby fed"
  end
end
