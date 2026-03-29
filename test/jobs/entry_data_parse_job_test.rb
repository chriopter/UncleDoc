require "test_helper"

class EntryDataParseJobTest < ActiveJob::TestCase
  test "saves parsed data onto the entry" do
    person = Person.create!(name: "Peter", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(note: "Peter has fever 39.2", occurred_at: Time.current, data: [], parse_status: "pending")

    result = EntryDataParser::Result.new(data: [ { "type" => "temperature", "value" => 39.2, "unit" => "C", "flag" => "high" } ])
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

    assert_equal "temperature", entry.reload.data.first["type"]
    assert_equal 39.2, entry.data.first["value"]
    assert_equal "parsed", entry.parse_status
    assert_equal 3, broadcast_calls.size
  end
end
