require "test_helper"

class ResearchChatResponseJobTest < ActiveJob::TestCase
  test "job attaches the health entry tool to the latest user message" do
    person = Person.create!(name: "Tool Jules", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    chat = person.build_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    user_message = chat.add_message(role: :user, content: "Ibuprofen 10mg")
    assistant_message = chat.messages.create!(role: :assistant, content: "", message_kind: "streaming")

    fake_llm_chat = Object.new
    attached_tool = nil
    attached_calls = nil
    fake_llm_chat.define_singleton_method(:with_tool) do |tool, calls: nil|
      attached_tool = tool
      attached_calls = calls
      self
    end
    fake_llm_chat.define_singleton_method(:on_new_message) { |&block| @on_new = block }
    fake_llm_chat.define_singleton_method(:on_end_message) { |&block| @on_end = block }
    fake_llm_chat.define_singleton_method(:complete) do |&block|
      block.call(Struct.new(:content).new("Saved.")) if block
      Struct.new(:content, :input_tokens, :output_tokens, :cached_tokens, :cache_creation_tokens, :thinking, :thinking_tokens).new("Saved.", 1, 2, 0, 0, nil, 0)
    end

    Chat.class_eval do
      alias_method :__original_to_llm_for_tool_test, :to_llm

      define_method(:to_llm) { fake_llm_chat }
    end

    ResearchChatResponseJob.perform_now(chat.id, assistant_message.id, "en")
  ensure
    if Chat.method_defined?(:__original_to_llm_for_tool_test)
      Chat.class_eval do
        alias_method :to_llm, :__original_to_llm_for_tool_test
        remove_method :__original_to_llm_for_tool_test
      end
    end

    assert_instance_of RecordHealthEntryTool, attached_tool
    assert_equal :one, attached_calls
    assert_equal user_message, attached_tool.instance_variable_get(:@message)
    assert_equal "Saved.", assistant_message.reload.content
  end

  test "job adds fallback assistant message when llm call fails" do
    person = Person.create!(name: "Fail Finn", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    chat = person.build_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    chat.add_message(role: :user, content: "Hello?")
    assistant_message = chat.messages.create!(role: :assistant, content: "", message_kind: "streaming")

    Chat.class_eval do
      alias_method :__original_to_llm_for_failure_test, :to_llm

      define_method(:to_llm) do
        Class.new do
          def with_tool(_tool, calls: nil) = self
          def on_new_message(&block) = @on_new = block
          def on_end_message(&block) = @on_end = block
          def complete(...) = raise RubyLLM::RateLimitError, "too many requests"
        end.new
      end
    end

    ResearchChatResponseJob.perform_now(chat.id, assistant_message.id, "en")
  ensure
    if Chat.method_defined?(:__original_to_llm_for_failure_test)
      Chat.class_eval do
        alias_method :to_llm, :__original_to_llm_for_failure_test
        remove_method :__original_to_llm_for_failure_test
      end
    end

    assert_equal I18n.t("chat.request_failed", locale: :en), assistant_message.reload.content
  end

  test "job also handles non ruby_llm standard errors" do
    person = Person.create!(name: "Crash Cora", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    chat = person.build_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    chat.add_message(role: :user, content: "Hi")
    assistant_message = chat.messages.create!(role: :assistant, content: "", message_kind: "streaming")

    Chat.class_eval do
      alias_method :__original_to_llm_for_standard_error_test, :to_llm

      define_method(:to_llm) do
        Class.new do
          def with_tool(_tool, calls: nil) = self
          def on_new_message(&block) = @on_new = block
          def on_end_message(&block) = @on_end = block
          def complete(...) = raise StandardError, "boom"
        end.new
      end
    end

    ResearchChatResponseJob.perform_now(chat.id, assistant_message.id, "en")
  ensure
    if Chat.method_defined?(:__original_to_llm_for_standard_error_test)
      Chat.class_eval do
        alias_method :to_llm, :__original_to_llm_for_standard_error_test
        remove_method :__original_to_llm_for_standard_error_test
      end
    end

    assert_equal I18n.t("chat.request_failed", locale: :en), assistant_message.reload.content
  end
end
