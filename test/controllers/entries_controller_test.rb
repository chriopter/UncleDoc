require "test_helper"

class EntriesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
  end

  test "creates free text entry and enqueues parsing" do
    UserPreference.current.update!(llm_provider: "ollama", llm_model: "llama3")

    assert_enqueued_with(job: EntryDataParseJob) do
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            input: "Peter has fever 39.2",
            occurred_at: "2026-03-29T10:15"
          }
        }
      end
    end

    entry = Entry.order(:created_at).last
    assert_equal "Peter has fever 39.2", entry.input
    assert_equal [], entry.facts
    assert_equal [], entry.parseable_data
    assert_equal "pending", entry.parse_status
    assert_equal Time.zone.parse("2026-03-29T10:15"), entry.occurred_at
  end

  test "creates free text entry without enqueueing when llm is not configured" do
    UserPreference.current.update!(llm_provider: "openai", llm_model: nil)

    assert_no_enqueued_jobs only: EntryDataParseJob do
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            input: "Peter has fever 39.2",
            occurred_at: "2026-03-29T10:15"
          }
        }
      end
    end

    assert_equal "skipped", Entry.order(:created_at).last.parse_status
  end

  test "defaults occurred_at to current time when omitted" do
    travel_to Time.zone.local(2026, 3, 29, 11, 45) do
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            input: "Quick input"
          }
        }
      end
    end

    assert_equal Time.zone.local(2026, 3, 29, 11, 45), Entry.order(:created_at).last.occurred_at
  end

  test "creates entry with direct parseable_data and skips parsing" do
    assert_no_enqueued_jobs only: EntryDataParseJob do
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            input: "Bottle 120ml",
            occurred_at: "2026-03-29T10:15",
            parseable_data: '[{"type":"bottle_feeding","value":120,"unit":"ml"}]'
          }
        }
      end
    end

    entry = Entry.order(:created_at).last
    assert_equal [ "Bottle feeding 120 ml" ], entry.facts
    assert_equal "bottle_feeding", entry.parseable_data.first["type"]
    assert_equal "parsed", entry.parse_status
  end

  test "creates free text entry even before parse_status migration is loaded" do
    entry_singleton = Entry.singleton_class
    original_column_names = Entry.column_names
    entry_singleton.alias_method :__original_column_names_for_test, :column_names
    entry_singleton.define_method(:column_names) { original_column_names - [ "parse_status" ] }

    begin
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            input: "Wate 5 bagel",
            occurred_at: "2026-03-29T09:03"
          }
        }
      end
    ensure
      entry_singleton.alias_method :column_names, :__original_column_names_for_test
      entry_singleton.remove_method :__original_column_names_for_test
    end

    assert_response :redirect
  end

  test "updates input and enqueues parsing again" do
    UserPreference.current.update!(llm_provider: "ollama", llm_model: "llama3")
    entry = @person.entries.create!(input: "Ate 5 donuts", occurred_at: Time.zone.parse("2026-03-29T09:38"), facts: [ "Food donuts" ], parseable_data: [ { "type" => "food", "value" => "donuts" } ], parse_status: "parsed")

    assert_enqueued_with(job: EntryDataParseJob) do
      patch person_entry_url(@person, entry), params: {
        entry: {
          input: "Ate 5 ibuprofen",
          occurred_at: "2026-03-29T09:38"
        }
      }
    end

    entry.reload
    assert_equal "Ate 5 ibuprofen", entry.input
    assert_equal [], entry.facts
    assert_equal [], entry.parseable_data
    assert_equal "pending", entry.parse_status
  end

  test "updates input without enqueueing when llm is not configured" do
    UserPreference.current.update!(llm_provider: "openai", llm_model: nil)
    entry = @person.entries.create!(input: "Ate 5 donuts", occurred_at: Time.zone.parse("2026-03-29T09:38"), facts: [ "Food donuts" ], parseable_data: [ { "type" => "food", "value" => "donuts" } ], parse_status: "parsed")

    assert_no_enqueued_jobs only: EntryDataParseJob do
      patch person_entry_url(@person, entry), params: {
        entry: {
          input: "Ate 6 donuts",
          occurred_at: "2026-03-29T09:38"
        }
      }
    end

    entry.reload
    assert_equal [], entry.facts
    assert_equal [], entry.parseable_data
    assert_equal "skipped", entry.parse_status
  end

  test "free text entry flows from create through parse job to rendered log" do
    UserPreference.current.update!(llm_provider: "ollama", llm_model: "llama3")

    parser_singleton = EntryDataParser.singleton_class
    parser_singleton.alias_method :__original_call_for_test, :call
    parser_singleton.define_method(:call) do |**|
      EntryDataParser::Result.new(
        facts: [ "Bottle feeding 120 ml", "Diaper wet" ],
        parseable_data: [
          { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" },
          { "type" => "diaper", "wet" => true, "solid" => false }
        ],
        occurred_at: Time.zone.local(2026, 3, 28, 10, 5, 0)
      )
    end

    begin
      perform_enqueued_jobs only: EntryDataParseJob do
        post person_entries_url(@person), params: {
          entry: {
            input: "peter drank 120 ml bottle and diaper wet",
            occurred_at: "2026-03-29T10:15"
          }
        }
      end
    ensure
      parser_singleton.alias_method :call, :__original_call_for_test
      parser_singleton.remove_method :__original_call_for_test
    end

    entry = Entry.order(:created_at).last
    assert_equal [ "Bottle feeding 120 ml", "Diaper wet" ], entry.facts
    assert_equal Time.zone.local(2026, 3, 28, 10, 5, 0), entry.occurred_at
    assert_equal "parsed", entry.parse_status

    get person_log_url(person_slug: @person.name)

    assert_response :success
    assert_includes @response.body, "Bottle feeding 120 ml"
    assert_includes @response.body, "Diaper wet"
    assert_includes @response.body, "peter drank 120 ml bottle and diaper wet"
  end
end
