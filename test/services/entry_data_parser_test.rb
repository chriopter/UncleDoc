require "test_helper"

class EntryDataParserTest < ActiveSupport::TestCase
  test "falls back to extracted document text when multimodal request fails" do
    person = Person.create!(name: "Parser Fallback", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(input: "seed", occurred_at: Time.current, facts: [], parseable_data: [], parse_status: "pending")
    entry.documents.attach(io: StringIO.new("Ibuprofen 400mg invoice"), filename: "invoice.txt", content_type: "text/plain")

    preference = UserPreference.current
    preference.llm_api_key = "test-key"
    preference.llm_provider = "openrouter"
    preference.llm_model = "openai/gpt-5.4"
    preference.save!

    multimodal_singleton = LlmMultimodalRequest.singleton_class
    chat_singleton = LlmChatRequest.singleton_class

    multimodal_singleton.alias_method :__original_multimodal_call_for_fallback_test, :call
    chat_singleton.alias_method :__original_chat_call_for_fallback_test, :call

    captured_message = nil

    multimodal_singleton.define_method(:call) { |**| raise StandardError, "multimodal failed" }
    chat_singleton.define_method(:call) do |**kwargs|
      captured_message = kwargs[:messages].last[:content]

      LlmChatRequest::Response.new(
        content: { facts: [ "Medication ibuprofen 400 mg" ], parseable_data: [ { type: "medication", value: "ibuprofen", dose: "400mg" } ], occurred_at: nil, llm_response: { status: "structured", confidence: "medium", note: "Fallback text extraction used." } }.to_json,
        status_code: 200,
        body: "{}"
      )
    end

    result = EntryDataParser.call(input: "", preference:, entry: entry)

    assert_includes captured_message, "Ibuprofen 400mg invoice"
    assert_equal [ "Medication ibuprofen 400 mg" ], result.facts
    assert_equal "medication", result.parseable_data.first["type"]
  ensure
    if multimodal_singleton.method_defined?(:__original_multimodal_call_for_fallback_test)
      multimodal_singleton.alias_method :call, :__original_multimodal_call_for_fallback_test
      multimodal_singleton.remove_method :__original_multimodal_call_for_fallback_test
    end
    if chat_singleton.method_defined?(:__original_chat_call_for_fallback_test)
      chat_singleton.alias_method :call, :__original_chat_call_for_fallback_test
      chat_singleton.remove_method :__original_chat_call_for_fallback_test
    end
  end
end
