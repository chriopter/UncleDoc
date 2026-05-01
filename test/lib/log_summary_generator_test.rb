require "test_helper"

class LogSummaryGeneratorTest < ActiveSupport::TestCase
  test "base UncleDoc prompt treats appointments goals and tasks as patient context" do
    prompt = LogSummaryGenerator.system_prompt

    assert_includes prompt, "appointments, open goals, and open tasks"
    assert_includes prompt, "first-class patient-record context"
    assert_includes prompt, "new logged activity supports or conflicts with an open goal"
  end

  test "formats structured baby entries for llm prompts" do
    person = Person.create!(name: "Demo Mila", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    entry = person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 29, 9, 0),
      input: "Baby fed",
      facts: [ "Bottle feeding 120 ml" ],
      parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ]
    )

    formatted = LogSummaryGenerator.formatted_entries([ entry ])

    assert_includes formatted, "Bottle feeding 120 ml"
    assert_includes formatted, "bottle_feeding 120 ml"
    assert_includes formatted, "Baby fed"
  end

  test "returns summary text" do
    preference = AppSetting.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Demo Mila", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    entry = person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 29, 9, 0),
      input: "Baby fed",
      facts: [ "Bottle feeding 120 ml" ],
      parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ]
    )

    request_singleton = LlmChatRequest.singleton_class
    request_singleton.alias_method :__original_call_for_summary_test, :call
    request_singleton.define_method(:call) do |**|
      LlmChatRequest::Response.new(content: "All good", status_code: 200, body: "{}")
    end

    begin
      result = LogSummaryGenerator.call(person: person, entries: [ entry ], preference: preference)
    ensure
      request_singleton.alias_method :call, :__original_call_for_summary_test
      request_singleton.remove_method :__original_call_for_summary_test
    end

    assert_equal "All good", result.summary
  end
end
