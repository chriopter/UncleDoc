class ResearchChatContextRefreshJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(person_id, locale = nil)
    person = Person.find_by(id: person_id)
    return unless person

    chat = person.chat
    return unless chat

    I18n.with_locale(locale.presence || UserPreference.current.locale || I18n.default_locale) do
      return unless ResearchChatContext.refresh_needed?(chat)

      ResearchChatContext.refresh!(chat, locale: I18n.locale)
    end
  end
end
