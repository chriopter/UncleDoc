require "test_helper"

class ResearchChatResponseJobTest < ActiveJob::TestCase
  test "job adds fallback assistant message when llm call fails" do
    person = Person.create!(name: "Fail Finn", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    chat = person.build_llm_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    chat.add_message(role: :user, content: "Hello?")

    LlmChat.class_eval do
      alias_method :__original_complete_for_failure_test, :complete

      def complete(...)
        raise RubyLLM::RateLimitError.new("too many requests")
      end
    end

    ResearchChatResponseJob.perform_now(chat.id, "en")
  ensure
    if LlmChat.method_defined?(:__original_complete_for_failure_test)
      LlmChat.class_eval do
        alias_method :complete, :__original_complete_for_failure_test
        remove_method :__original_complete_for_failure_test
      end
    end

    assert_equal I18n.t("chat.request_failed"), chat.llm_messages.visible.where(role: "assistant").last&.content
  end

  test "job also handles non ruby_llm standard errors" do
    person = Person.create!(name: "Crash Cora", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")

    chat = person.build_llm_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    chat.add_message(role: :user, content: "Hi")

    LlmChat.class_eval do
      alias_method :__original_complete_for_standard_error_test, :complete

      def complete(...)
        raise StandardError, "boom"
      end
    end

    ResearchChatResponseJob.perform_now(chat.id, "en")
  ensure
    if LlmChat.method_defined?(:__original_complete_for_standard_error_test)
      LlmChat.class_eval do
        alias_method :complete, :__original_complete_for_standard_error_test
        remove_method :__original_complete_for_standard_error_test
      end
    end

    assert_equal I18n.t("chat.request_failed"), chat.llm_messages.visible.where(role: "assistant").last&.content
  end
end
