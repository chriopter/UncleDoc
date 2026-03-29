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
            note: "Peter has fever 39.2",
            occurred_at: "2026-03-29T10:15"
          }
        }
      end
    end

    entry = Entry.order(:created_at).last
    assert_equal "Peter has fever 39.2", entry.note
    assert_equal [], entry.data
    assert_equal "pending", entry.parse_status
    assert_equal Time.zone.parse("2026-03-29T10:15"), entry.occurred_at
  end

  test "creates free text entry without enqueueing when llm is not configured" do
    UserPreference.current.update!(llm_provider: "openai", llm_model: nil)

    assert_no_enqueued_jobs only: EntryDataParseJob do
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            note: "Peter has fever 39.2",
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
            note: "Quick note"
          }
        }
      end
    end

    assert_equal Time.zone.local(2026, 3, 29, 11, 45), Entry.order(:created_at).last.occurred_at
  end

  test "creates entry with direct data and skips parsing" do
    assert_no_enqueued_jobs only: EntryDataParseJob do
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            note: "Bottle 120ml",
            occurred_at: "2026-03-29T10:15",
            data: '[{"type":"bottle_feeding","value":120,"unit":"ml"}]'
          }
        }
      end
    end

    entry = Entry.order(:created_at).last
    assert_equal "bottle_feeding", entry.data.first["type"]
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
            note: "Wate 5 bagel",
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

  test "updates note and enqueues parsing again" do
    UserPreference.current.update!(llm_provider: "ollama", llm_model: "llama3")
    entry = @person.entries.create!(note: "Ate 5 donuts", occurred_at: Time.zone.parse("2026-03-29T09:38"), data: [ { "type" => "food", "value" => "donuts" } ], parse_status: "parsed")

    assert_enqueued_with(job: EntryDataParseJob) do
      patch person_entry_url(@person, entry), params: {
        entry: {
          note: "Ate 5 ibuprofen",
          occurred_at: "2026-03-29T09:38"
        }
      }
    end

    entry.reload
    assert_equal "Ate 5 ibuprofen", entry.note
    assert_equal [], entry.data
    assert_equal "pending", entry.parse_status
  end

  test "updates note without enqueueing when llm is not configured" do
    UserPreference.current.update!(llm_provider: "openai", llm_model: nil)
    entry = @person.entries.create!(note: "Ate 5 donuts", occurred_at: Time.zone.parse("2026-03-29T09:38"), data: [ { "type" => "food", "value" => "donuts" } ], parse_status: "parsed")

    assert_no_enqueued_jobs only: EntryDataParseJob do
      patch person_entry_url(@person, entry), params: {
        entry: {
          note: "Ate 6 donuts",
          occurred_at: "2026-03-29T09:38"
        }
      }
    end

    entry.reload
    assert_equal [], entry.data
    assert_equal "skipped", entry.parse_status
  end
end
