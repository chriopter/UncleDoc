require "test_helper"

class ResearchChatResponseJobTest < ActiveJob::TestCase
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

    assert_equal I18n.t("chat.request_failed"), assistant_message.reload.content
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

    assert_equal I18n.t("chat.request_failed"), assistant_message.reload.content
  end
end
