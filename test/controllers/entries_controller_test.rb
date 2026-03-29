require "test_helper"

class EntriesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
  end

  test "creates free text entry and enqueues parsing" do
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
end
