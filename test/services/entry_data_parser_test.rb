require "test_helper"

class EntryDataParserTest < ActiveSupport::TestCase
  test "system prompt includes baby and elderly examples" do
    prompt = EntryDataParser.system_prompt

    assert_includes prompt, "Peter diaper wet and solid"
    assert_includes prompt, "Elderly patient WBC 11.2 G/L"
  end

  test "call sanitizes fenced json arrays" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    parser_singleton = EntryDataParser.singleton_class
    parser_singleton.alias_method :__original_request_completion_for_test, :request_completion
    parser_singleton.define_method(:request_completion) { |_note, _preference| "```json\n[{\"type\":\"breastfeeding\",\"value\":\"18\",\"unit\":\"minutes\",\"side\":\"left\"}]\n```" }

    begin
      result = EntryDataParser.call(note: "Peter breastfed left side for 18 minutes", preference: preference)

      assert_nil result.error
      assert_equal [ { "type" => "breast_feeding", "value" => 18, "unit" => "min", "side" => "left" } ], result.data
    ensure
      parser_singleton.alias_method :request_completion, :__original_request_completion_for_test
      parser_singleton.remove_method :__original_request_completion_for_test
    end
  end

  test "request completion sends system prompt and note" do
    preference = UserPreference.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    captured_request = nil
    fake_response = Struct.new(:code, :body).new("200", { choices: [ { message: { content: "[]" } } ] }.to_json)

    http_singleton = Net::HTTP.singleton_class
    http_singleton.alias_method :__original_start_for_test, :start
    http_singleton.define_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured_request = request
        fake_response
      end
      block.call(http)
    end

    begin
      EntryDataParser.request_completion("Peter has fever 39.2", preference)
    ensure
      http_singleton.alias_method :start, :__original_start_for_test
      http_singleton.remove_method :__original_start_for_test
    end

    payload = JSON.parse(captured_request.body)
    assert_equal "llama3", payload["model"]
    assert_equal 0, payload["temperature"]
    assert_includes payload["messages"][0]["content"], "Peter diaper wet and solid"
    assert_equal "Note: Peter has fever 39.2", payload["messages"][1]["content"]
  end
end
