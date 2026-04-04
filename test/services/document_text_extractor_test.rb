require "test_helper"

class DocumentTextExtractorTest < ActiveSupport::TestCase
  test "extracts text from plain text blob" do
    person = Person.create!(name: "Doc Test", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(input: "seed", occurred_at: Time.current, facts: [], parseable_data: [], parse_status: "pending")
    entry.documents.attach(io: StringIO.new("Doctor invoice total 42 EUR"), filename: "invoice.txt", content_type: "text/plain")

    extracted = DocumentTextExtractor.extract_many(entry.documents.blobs)

    assert_includes extracted, "invoice.txt"
    assert_includes extracted, "Doctor invoice total 42 EUR"
  end
end
