require "test_helper"

class LlmChatRequestTest < ActiveSupport::TestCase
  test "returns parsed content" do
    preference = AppSetting.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Peter", birth_date: Date.new(2020, 1, 1))

    fake_response = Struct.new(:code, :body).new("200", { choices: [ { message: { content: "[]" } } ] }.to_json)

    http_singleton = Net::HTTP.singleton_class
    http_singleton.alias_method :__original_start_for_test, :start
    http_singleton.define_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| fake_response }
      block.call(http)
    end

    begin
      response = LlmChatRequest.call(
        request_kind: "entry_parse",
        preference: preference,
        person: person,
        messages: [ { role: "user", content: "hello" } ],
        temperature: 0
      )
    ensure
      http_singleton.alias_method :start, :__original_start_for_test
      http_singleton.remove_method :__original_start_for_test
    end

    assert_equal "[]", response.content
  end

  test "raises on failed response" do
    preference = AppSetting.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    fake_response = Struct.new(:code, :body).new("500", '{"error":"boom"}')

    http_singleton = Net::HTTP.singleton_class
    http_singleton.alias_method :__original_start_for_test, :start
    http_singleton.define_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) { |_request| fake_response }
      block.call(http)
    end

    begin
      assert_raises(RuntimeError) do
        LlmChatRequest.call(
          request_kind: "log_summary",
          preference: preference,
          messages: [ { role: "user", content: "hello" } ]
        )
      end
    ensure
      http_singleton.alias_method :start, :__original_start_for_test
      http_singleton.remove_method :__original_start_for_test
    end
  end
end
