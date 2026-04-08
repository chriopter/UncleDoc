require "test_helper"

class LlmChatRequestTest < ActiveSupport::TestCase
  test "returns parsed content" do
    preference = AppSetting.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Peter", birth_date: Date.new(2020, 1, 1))

    fake_chat = Object.new
    fake_chat.define_singleton_method(:add_message) { |_attrs| true }
    fake_chat.define_singleton_method(:complete) do
      Struct.new(:content, :raw).new("[]", Struct.new(:status, :body).new(200, '{"ok":true}'))
    end

    runtime_singleton = ResearchChatRuntime.singleton_class
    runtime_singleton.alias_method :__original_build_chat_for_test, :build_chat
    runtime_singleton.define_method(:build_chat) { |**| fake_chat }

    begin
      response = LlmChatRequest.call(
        request_kind: "entry_parse",
        preference: preference,
        person: person,
        messages: [ { role: "user", content: "hello" } ],
        temperature: 0
      )
    ensure
      runtime_singleton.alias_method :build_chat, :__original_build_chat_for_test
      runtime_singleton.remove_method :__original_build_chat_for_test
    end

    assert_equal "[]", response.content
    assert_equal 200, response.status_code
  end

  test "raises on failed response" do
    preference = AppSetting.current
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    fake_chat = Object.new
    fake_chat.define_singleton_method(:add_message) { |_attrs| true }
    fake_chat.define_singleton_method(:complete) { raise StandardError, "boom" }

    runtime_singleton = ResearchChatRuntime.singleton_class
    runtime_singleton.alias_method :__original_build_chat_for_error_test, :build_chat
    runtime_singleton.define_method(:build_chat) { |**| fake_chat }

    begin
      assert_raises(StandardError) do
        LlmChatRequest.call(
          request_kind: "log_summary",
          preference: preference,
          messages: [ { role: "user", content: "hello" } ]
        )
      end
    ensure
      runtime_singleton.alias_method :build_chat, :__original_build_chat_for_error_test
      runtime_singleton.remove_method :__original_build_chat_for_error_test
    end
  end
end
