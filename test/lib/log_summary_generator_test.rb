require "test_helper"

class LogSummaryGeneratorTest < ActiveSupport::TestCase
  test "formats structured baby entries for llm prompts" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
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
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    entry = person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 29, 9, 0),
      input: "Baby fed",
      facts: [ "Bottle feeding 120 ml" ],
      parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ]
    )

    fake_response = Struct.new(:code, :body).new("200", { choices: [ { message: { content: "All good" } } ] }.to_json)

    http_singleton = Net::HTTP.singleton_class
    http_singleton.alias_method :__original_start_for_test, :start
    http_singleton.define_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| fake_response }
      block.call(http)
    end

    begin
      result = LogSummaryGenerator.call(person: person, entries: [ entry ], preference: preference)
    ensure
      http_singleton.alias_method :start, :__original_start_for_test
      http_singleton.remove_method :__original_start_for_test
    end

    assert_equal "All good", result.summary
  end
end
