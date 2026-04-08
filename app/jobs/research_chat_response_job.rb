class ResearchChatResponseJob < ApplicationJob
  queue_as :default

  retry_on RubyLLM::RateLimitError, Timeout::Error, Errno::ECONNRESET, EOFError, SocketError, wait: 5.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError
  rescue_from(StandardError) do |error|
    chat_id, assistant_message_id, locale = arguments
    chat = Chat.find_by(id: chat_id)
    assistant_message = chat&.messages&.find_by(id: assistant_message_id)

    Rails.logger.warn("Research chat failed: #{error.class}: #{error.message}")

    I18n.with_locale(locale.presence || I18n.default_locale) do
      if assistant_message.present?
        assistant_message.update!(content: I18n.t("chat.request_failed"), message_kind: "message")
      else
        chat&.add_message(role: :assistant, content: I18n.t("chat.request_failed"))
      end
    end
  end

  def perform(chat_id, assistant_message_id, locale)
    chat = Chat.includes(:person).find_by(id: chat_id)
    return unless chat

    assistant_message = chat.messages.find_by(id: assistant_message_id, role: "assistant")
    return unless assistant_message

    I18n.with_locale(locale.presence || I18n.default_locale) do
      setting = AppSetting.current
      ResearchChatRuntime.prepare!(chat, setting: setting)
      ResearchChatContext.refresh!(chat, locale:) if ResearchChatContext.refresh_needed?(chat)

      llm_chat = chat.to_llm
      llm_chat.on_new_message { nil }
      llm_chat.on_end_message { |_message| nil }

      response = llm_chat.complete do |chunk|
        next if chunk.content.blank?

        assistant_message.broadcast_append_chunk(chunk.content) if assistant_message.present?
      end

      assistant_message.update!(
        content: response.content.to_s,
        model: chat.model,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        cached_tokens: response.cached_tokens,
        cache_creation_tokens: response.cache_creation_tokens,
        thinking_text: response.thinking&.text,
        thinking_signature: response.thinking&.signature,
        thinking_tokens: response.thinking_tokens,
        message_kind: "message"
      )
    end
  end
end
