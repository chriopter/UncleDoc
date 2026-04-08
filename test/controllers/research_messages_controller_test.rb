require "test_helper"

class ResearchMessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @person = Person.create!(name: "Research Nora", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
  end

  test "posting a chat message saves the user turn and enqueues the response job" do
    assert_enqueued_with(job: ResearchChatResponseJob, args: ->(args) { args.first.is_a?(Integer) && args.second.is_a?(Integer) && args.third == I18n.locale.to_s }) do
      post person_chat_path(person_slug: @person.name), params: { message: { content: "How is she doing?" } }, as: :turbo_stream
    end

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_equal [ "How is she doing?" ], @person.chat.messages.visible.where(role: "user").pluck(:content)
    assert_equal 1, @person.chat.messages.visible.where(role: "assistant", message_kind: "streaming").count
    assert_includes response.body, "research_chat_form"
    assert_includes response.body, "chat_welcome"
  end

  test "posting without model configuration shows an inline error" do
    AppSetting.current.update!(llm_model: nil)

    post person_chat_path(person_slug: @person.name), params: { message: { content: "Hello" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("log_summary.states.missing_model")
    assert_nil @person.chat
  end

  test "blank message does not create a chat or enqueue a job" do
    assert_no_enqueued_jobs only: ResearchChatResponseJob do
      post person_chat_path(person_slug: @person.name), params: { message: { content: "   " } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_nil @person.chat
  end

  test "response job refreshes stale context before generating the assistant turn" do
    @person.entries.create!(occurred_at: Time.zone.local(2026, 4, 8, 9, 0), input: "No fever", facts: [ "No fever" ], parseable_data: [])

    chat = @person.build_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    ResearchChatContext.refresh!(chat, locale: :en)
    chat.add_message(role: :user, content: "Give me a summary")

    travel 1.minute do
      @person.entries.create!(occurred_at: Time.zone.local(2026, 4, 8, 10, 0), input: "Fever 38.4", facts: [ "Fever 38.4 C" ], parseable_data: [ { "type" => "temperature", "value" => 38.4, "unit" => "C" } ])
    end

    assistant_message = chat.messages.create!(role: :assistant, content: "", message_kind: "streaming")
    fake_llm_chat = Object.new
    fake_llm_chat.define_singleton_method(:on_new_message) { |&block| @on_new = block }
    fake_llm_chat.define_singleton_method(:on_end_message) { |&block| @on_end = block }
    fake_llm_chat.define_singleton_method(:complete) do |&block|
      block.call(Struct.new(:content).new("Latest data used.")) if block
      Struct.new(:content, :input_tokens, :output_tokens, :cached_tokens, :cache_creation_tokens, :thinking, :thinking_tokens).new("Latest data used.", 10, 20, 0, 0, nil, 0)
    end

    Chat.class_eval do
      alias_method :__original_to_llm_for_research_test, :to_llm

      define_method(:to_llm) { fake_llm_chat }
    end

    perform_enqueued_jobs do
      ResearchChatResponseJob.perform_later(chat.id, assistant_message.id, "en")
    end
  ensure
    if Chat.method_defined?(:__original_to_llm_for_research_test)
      Chat.class_eval do
        alias_method :to_llm, :__original_to_llm_for_research_test
        remove_method :__original_to_llm_for_research_test
      end
    end

    if defined?(chat) && chat.present?
      chat.reload
      assert_includes chat.context_message.content, "Fever 38.4 C"
      assert_equal I18n.t("chat.context_refreshed"), chat.messages.visible.where(message_kind: "context_notice").last&.content
      assert_equal "Latest data used.", chat.messages.visible.where(role: "assistant").last&.content
    end
  end
end
