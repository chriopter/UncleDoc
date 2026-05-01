require "test_helper"

class EntryDataParseJobTest < ActiveJob::TestCase
  test "saves parsed parseable_data onto the entry" do
    person = Person.create!(name: "Peter", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(input: "Peter has fever 39.2", occurred_at: Time.current, facts: [], parseable_data: [], parse_status: "pending")

    result = EntryDataParser::Result.new(facts: [ "Temperature 39.2 C high" ], parseable_data: [ { "type" => "temperature", "value" => 39.2, "unit" => "C", "flag" => "high" } ], occurred_at: Time.zone.local(2026, 3, 28, 22, 10, 0), llm_response: { "status" => "structured", "confidence" => "high", "note" => "Canonical structured data extracted successfully." })
    broadcast_calls = []

    parser_singleton = EntryDataParser.singleton_class
    parser_singleton.alias_method :__original_call_for_test, :call
    parser_singleton.define_method(:call) { |**| result }

    channel_singleton = Turbo::StreamsChannel.singleton_class
    channel_singleton.alias_method :__original_broadcast_replace_to_for_test, :broadcast_replace_to
    channel_singleton.define_method(:broadcast_replace_to) { |*args, **kwargs| broadcast_calls << [ args, kwargs ] }

    begin
      EntryDataParseJob.perform_now(entry.id)
    ensure
      parser_singleton.alias_method :call, :__original_call_for_test
      parser_singleton.remove_method :__original_call_for_test
      channel_singleton.alias_method :broadcast_replace_to, :__original_broadcast_replace_to_for_test
      channel_singleton.remove_method :__original_broadcast_replace_to_for_test
    end

    assert_equal [ "Temperature 39.2 C high" ], entry.reload.facts
    assert_equal "temperature", entry.reload.parseable_data.first["type"]
    assert_equal 39.2, entry.parseable_data.first["value"]
    assert_equal Time.zone.local(2026, 3, 28, 22, 10, 0), entry.occurred_at
    assert_equal({ "status" => "structured", "confidence" => "high", "note" => "Canonical structured data extracted successfully." }, entry.llm_response)
    assert_equal "parsed", entry.parse_status
    assert_equal 12, broadcast_calls.size
  end

  test "does not change occurred_at when parser returns no inferred timestamp" do
    person = Person.create!(name: "Peter", birth_date: Date.new(2020, 1, 1))
    original_time = Time.zone.local(2024, 6, 2, 9, 30, 0)
    entry = person.entries.create!(input: "old plain note", occurred_at: original_time, facts: [], parseable_data: [], parse_status: "pending")

    result = EntryDataParser::Result.new(facts: [ "General note seems fine today" ], parseable_data: [], occurred_at: nil, llm_response: { "status" => "facts_only", "confidence" => "medium", "note" => "No canonical structured data could be extracted from the note." })

    parser_singleton = EntryDataParser.singleton_class
    parser_singleton.alias_method :__original_call_for_test, :call
    parser_singleton.define_method(:call) { |**| result }

    begin
      EntryDataParseJob.perform_now(entry.id)
    ensure
      parser_singleton.alias_method :call, :__original_call_for_test
      parser_singleton.remove_method :__original_call_for_test
    end

    assert_equal original_time, entry.reload.occurred_at
    assert_equal({ "status" => "facts_only", "confidence" => "medium", "note" => "No canonical structured data could be extracted from the note." }, entry.llm_response)
  end
end
