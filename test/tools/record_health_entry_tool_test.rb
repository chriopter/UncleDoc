require "test_helper"

class RecordHealthEntryToolTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates one parsed entry from the chat message and one document" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Tool Tina", birth_date: Date.new(2024, 1, 1))
    chat = person.build_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    message = chat.add_message(role: :user, content: "Bitte speichern")
    message.attachments.attach(
      io: StringIO.new("Befund und Rechnung"),
      filename: "befund-rechnung.txt",
      content_type: "text/plain"
    )

    parser_result = EntryDataParser::Result.new(
      fact_objects: [
        { "text" => "Laborbefund vorhanden", "kind" => "note" },
        { "text" => "Rechnungssumme 20,11 EUR", "kind" => "note" }
      ],
      document: {
        "types" => [ "lab_report", "invoice" ],
        "title" => "Befund und Rechnung",
        "total_amount" => 20.11,
        "currency" => "EUR"
      },
      llm: { "status" => "structured" }
    )

    original_call = EntryDataParser.method(:call)
    EntryDataParser.define_singleton_method(:call) { |**| parser_result }

    result = RecordHealthEntryTool.new(person:, message:).execute(reason: "uploaded document")

    entry = person.entries.first!
    assert_equal "parsed", entry.parse_status
    assert_equal "Bitte speichern", entry.input
    assert_equal [ "befund-rechnung.txt" ], entry.document_names
    assert_match(/\Achat:message:#{message.id}:attachment:\d+\z/, entry.source_ref)
    assert_equal [ "lab_report", "invoice" ], entry.document_types
    assert_equal "20,11 EUR", entry.invoice_total_label
    assert_equal "parsed", result[:status]
    assert_equal [ entry.id ], result[:entry_ids]
    assert_equal [ "lab_report", "invoice" ], result[:entries].first[:document_types]
    assert_equal "uploaded document", result[:reason]
  ensure
    EntryDataParser.define_singleton_method(:call, original_call) if defined?(original_call) && original_call
  end

  test "creates one parsed entry per chat attachment" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Tool Mira", birth_date: Date.new(2024, 1, 1))
    chat = person.build_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    message = chat.add_message(role: :user, content: "Hausratversicherung Unterlagen")
    message.attachments.attach(
      io: StringIO.new("Infobrief"),
      filename: "03_Infobrief.pdf",
      content_type: "text/plain"
    )
    message.attachments.attach(
      io: StringIO.new("Folgerechnung"),
      filename: "02_Folgerechnung.pdf",
      content_type: "text/plain"
    )
    message.attachments.attach(
      io: StringIO.new("Versicherungsschein"),
      filename: "01_Versicherungsschein.pdf",
      content_type: "text/plain"
    )

    parser_result = EntryDataParser::Result.new(
      fact_objects: [ { "text" => "Hausratversicherung erkannt", "kind" => "note" } ],
      document: { "type" => "insurance", "title" => "Hausratversicherung" },
      llm: { "status" => "structured" }
    )

    original_call = EntryDataParser.method(:call)
    EntryDataParser.define_singleton_method(:call) { |**| parser_result }

    result = RecordHealthEntryTool.new(person:, message:).execute(reason: "uploaded documents")

    entries = person.entries.order(:created_at).to_a
    assert_equal 3, entries.size
    assert_equal [ [ "03_Infobrief.pdf" ], [ "02_Folgerechnung.pdf" ], [ "01_Versicherungsschein.pdf" ] ], entries.map(&:document_names)
    assert_equal [ "Hausratversicherung Unterlagen", "", "" ], entries.map(&:input)
    assert entries.all? { |entry| entry.parse_status == "parsed" }
    assert entries.all? { |entry| entry.source_ref.match?(/\Achat:message:#{message.id}:attachment:\d+\z/) }
    assert_equal "parsed", result[:status]
    assert_equal entries.map(&:id), result[:entry_ids]
    assert_equal 3, result[:entries].size

    assert_no_difference("Entry.count") do
      RecordHealthEntryTool.new(person:, message:).execute(reason: "uploaded documents")
    end
  ensure
    EntryDataParser.define_singleton_method(:call, original_call) if defined?(original_call) && original_call
  end
end
