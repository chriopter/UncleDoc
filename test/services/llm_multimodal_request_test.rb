require "test_helper"

class LlmMultimodalRequestTest < ActiveSupport::TestCase
  test "rasterize_pdf uses higher resolution and more pages" do
    pdf_bytes = "%PDF-1.4 fake"
    captured_command = nil

    Open3.singleton_class.alias_method :__original_capture3_for_pdf_test, :capture3
    Open3.singleton_class.define_method(:capture3) do |*command|
      captured_command = command
      output_prefix = command.last
      File.binwrite("#{output_prefix}-1.png", "png-bytes")
      [ "", "", Struct.new(:success?).new(true) ]
    end

    result = LlmMultimodalRequest.rasterize_pdf(pdf_bytes)

    assert_equal [ "png-bytes" ], result
    assert_equal "pdftoppm", captured_command[0]
    assert_includes captured_command, "-r"
    assert_includes captured_command, "300"
    assert_includes captured_command, "-l"
    assert_includes captured_command, "5"
  ensure
    if Open3.singleton_class.method_defined?(:__original_capture3_for_pdf_test)
      Open3.singleton_class.alias_method :capture3, :__original_capture3_for_pdf_test
      Open3.singleton_class.remove_method :__original_capture3_for_pdf_test
    end
  end
end
