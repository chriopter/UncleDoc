class ResearchChatResponseJob < ApplicationJob
  queue_as :default

  def perform(chat_id, locale)
    chat = LlmChat.includes(:person).find_by(id: chat_id)
    return unless chat

    I18n.with_locale(locale.presence || I18n.default_locale) do
      setting = AppSetting.current
      ResearchChatRuntime.prepare!(chat, setting: setting)
      ResearchChatContext.refresh!(chat, locale:) if ResearchChatContext.refresh_needed?(chat)

      chat.complete do |chunk|
        next if chunk.content.blank?

        assistant_message = chat.messages.order(:id).last
        assistant_message.broadcast_append_chunk(chunk.content) if assistant_message.present?
      end
    end
  rescue StandardError => error
    Rails.logger.warn("Research chat failed: #{error.class}: #{error.message}")
    I18n.with_locale(locale.presence || I18n.default_locale) do
      chat&.add_message(role: :assistant, content: I18n.t("chat.request_failed"))
    end
  end
end
