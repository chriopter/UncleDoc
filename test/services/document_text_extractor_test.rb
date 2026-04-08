require "test_helper"

class DocumentTextExtractorTest < ActiveSupport::TestCase
  test "extract_pdf falls back to printable text when pdftotext is unavailable" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF simple printable invoice text"),
      filename: "sample.pdf",
      content_type: "application/pdf"
    )

    Open3.singleton_class.alias_method :__original_capture2_for_doc_test, :capture2
    Open3.singleton_class.define_method(:capture2) do |*_args|
      raise Errno::ENOENT, "pdftotext"
    end

    extracted = DocumentTextExtractor.extract_pdf(blob)

    assert_includes extracted, "PDF simple printable invoice text"
  ensure
    if Open3.singleton_class.method_defined?(:__original_capture2_for_doc_test)
      Open3.singleton_class.alias_method :capture2, :__original_capture2_for_doc_test
      Open3.singleton_class.remove_method :__original_capture2_for_doc_test
    end
  end
end
