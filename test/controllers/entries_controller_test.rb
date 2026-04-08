require "test_helper"
require "rack/test"

class EntriesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
  end

  def fake_pdf_upload(name: "report.pdf")
    tempfile = Tempfile.new([ File.basename(name, ".pdf"), ".pdf" ])
    tempfile.binmode
    tempfile.write(fake_pdf_content("Fabricated report for upload testing"))
    tempfile.rewind

    Rack::Test::UploadedFile.new(tempfile.path, "application/pdf", true, original_filename: name)
  end

  def fake_pdf_content(text)
    <<~PDF
      %PDF-1.4
      1 0 obj
      << /Type /Catalog /Pages 2 0 R >>
      endobj
      2 0 obj
      << /Type /Pages /Count 1 /Kids [3 0 R] >>
      endobj
      3 0 obj
      << /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << >> >>
      endobj
      4 0 obj
      << /Length 44 >>
      stream
      BT /F1 12 Tf 36 96 Td (#{text}) Tj ET
      endstream
      endobj
      xref
      0 5
      0000000000 65535 f
      0000000010 00000 n
      0000000063 00000 n
      0000000122 00000 n
      0000000226 00000 n
      trailer
      << /Root 1 0 R /Size 5 >>
      startxref
      319
      %%EOF
    PDF
  end

  test "creates free text entry and enqueues parsing" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

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
    AppSetting.current.update!(llm_provider: "openai", llm_model: nil)

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

  test "creates document-only entry and enqueues parsing" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    assert_enqueued_with(job: EntryDataParseJob) do
      assert_difference("Entry.count", 1) do
        post person_entries_url(@person), params: {
          entry: {
            input: "",
            occurred_at: "2026-03-29T10:15",
            documents: [ fake_pdf_upload(name: "invoice.pdf") ]
          }
        }
      end
    end

    entry = Entry.order(:created_at).last
    assert entry.documents.attached?
    assert_equal [ "invoice.pdf" ], entry.document_names
    assert_equal "pending", entry.parse_status
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
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
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
    AppSetting.current.update!(llm_provider: "openai", llm_model: nil)
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

  test "reparse forces a fresh parse even when input is unchanged" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    entry = @person.entries.create!(
      input: "40 Celsius fieber",
      occurred_at: Time.zone.parse("2026-03-31T17:47"),
      facts: [ "40 Celsius Fieber" ],
      parseable_data: [ { "type" => "temperature", "value" => 40, "unit" => "C", "flag" => "fever" } ],
      llm_response: { "status" => "structured" },
      parse_status: "parsed"
    )

    assert_enqueued_with(job: EntryDataParseJob) do
      patch reparse_person_entry_url(@person, entry)
    end

    assert_response :redirect
    entry.reload
    assert_equal [], entry.facts
    assert_equal [], entry.parseable_data
    assert_equal({}, entry.llm_response)
    assert_equal "pending", entry.parse_status
  end

  test "free text entry flows from create through parse job to rendered log" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    parser_singleton = EntryDataParser.singleton_class
    parser_singleton.alias_method :__original_call_for_test, :call
    parser_singleton.define_method(:call) do |**|
      EntryDataParser::Result.new(
        facts: [ "Bottle feeding 120 ml", "Diaper wet" ],
        parseable_data: [
          { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" },
          { "type" => "diaper", "wet" => true, "solid" => false }
        ],
        occurred_at: Time.zone.local(2026, 3, 28, 10, 5, 0),
        llm_response: { "status" => "structured", "confidence" => "high", "note" => "Canonical structured data extracted successfully." }
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

  test "document entry flows from create through parse job to rendered files tab" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    parser_singleton = EntryDataParser.singleton_class
    parser_singleton.alias_method :__original_call_for_document_test, :call
    parser_singleton.define_method(:call) do |**|
      EntryDataParser::Result.new(
        facts: [ "Doctor invoice follow-up needed" ],
        document: { "type" => "invoice", "title" => "Doctor invoice from March 2026" },
        parseable_data: [ { "type" => "todo", "value" => "Pay doctor invoice" } ],
        occurred_at: Time.zone.local(2026, 3, 28, 10, 5, 0),
        llm_response: { "status" => "structured", "confidence" => "high", "note" => "Document parsed successfully." }
      )
    end

    begin
      perform_enqueued_jobs only: EntryDataParseJob do
        post person_entries_url(@person), params: {
          entry: {
            input: "Invoice upload",
            occurred_at: "2026-03-29T10:15",
            documents: [ fake_pdf_upload(name: "doctor-invoice.pdf") ]
          }
        }
      end
    ensure
      parser_singleton.alias_method :call, :__original_call_for_document_test
      parser_singleton.remove_method :__original_call_for_document_test
    end

    entry = Entry.order(:created_at).last
    assert_equal [ "Doctor invoice follow-up needed" ], entry.facts
    assert_equal "invoice", entry.document_type
    assert_equal "Doctor invoice from March 2026", entry.document_title
    assert_equal "parsed", entry.parse_status

    get person_files_url(person_slug: @person.name)

    assert_response :success
    assert_includes @response.body, "doctor-invoice.pdf"
    assert_includes @response.body, "Doctor invoice from March 2026"
  end

  test "destroy removes an entry" do
    entry = @person.entries.create!(input: "RSV Impfung durchgeführt", occurred_at: Time.zone.parse("2026-03-29T09:38"), facts: [ "RSV Impfung durchgeführt" ], parseable_data: [ { "type" => "medication", "value" => "RSV Impfung" } ], parse_status: "parsed")

    assert_difference("Entry.count", -1) do
      delete person_entry_url(@person, entry)
    end

    assert_response :redirect
  end

  test "toggle todo updates app-managed completion state" do
    entry = @person.entries.create!(input: "todo bring card", occurred_at: Time.zone.parse("2026-04-02T09:38"), facts: [ "Bring vaccination card" ], parseable_data: [ { "type" => "todo", "value" => "bring vaccination card" } ], parse_status: "parsed", todo_done: false)

    patch toggle_todo_person_entry_url(@person, entry)

    assert_response :redirect
    assert entry.reload.todo_done?
    assert entry.todo_done_at.present?

    patch toggle_todo_person_entry_url(@person, entry)
    entry.reload
    assert_not entry.todo_done?
    assert_nil entry.todo_done_at
  end
end
