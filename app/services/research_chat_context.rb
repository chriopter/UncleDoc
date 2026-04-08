class ResearchChatContext
  def self.refresh!(chat, locale: I18n.locale)
    I18n.with_locale(locale) do
      chat.with_lock do
        latest_updated_at = latest_source_updated_at(chat.person)
        return if chat.context_message.present? && chat.context_source_updated_at == latest_updated_at

        context_message = chat.context_message || chat.messages.build(role: :system, message_kind: "context", hidden: true)
        context_message.content = system_prompt_for(chat.person)
        context_message.save!
        broadcast_context_preview(chat, context_message.content)

        if chat.context_source_updated_at.present? && chat.context_source_updated_at != latest_updated_at
          chat.messages.create!(role: :system, content: I18n.t("chat.context_refreshed"), message_kind: "context_notice")
        end

        chat.update!(
          context_refreshed_at: Time.current,
          context_source_updated_at: latest_updated_at
        )
      end
    end
  end

  def self.refresh_needed?(chat)
    chat.context_message.blank? || chat.context_source_updated_at != latest_source_updated_at(chat.person)
  end

  def self.system_prompt_for(person)
    entries = person.entries.order(occurred_at: :asc)

    <<~PROMPT.strip
      #{LogSummaryGenerator.system_prompt}

      # Patientenakte: #{person.name}

      #{patient_record_snapshot(person, entries)}

      Freshness rules:
      - This patient record snapshot is the source of truth for current health data.
      - If the current patient record conflicts with earlier assistant replies in this chat, prefer the current patient record.
      - Treat older assistant replies as historical conversation, not authoritative medical data.
    PROMPT
  end

  def self.patient_record_snapshot(person, entries)
    return I18n.t("chat.empty_record", name: person.name) if entries.empty?

    lines = entries.map do |entry|
      date = entry.occurred_at ? I18n.l(entry.occurred_at, format: :long) : I18n.t("chat.unknown_date")
      parts = []
      parts << entry.fact_summary if entry.fact_items.present?
      parts << entry.input if entry.input.present?

      if entry.fact_objects.present?
        data_parts = entry.fact_objects.filter_map do |item|
          next unless item.is_a?(Hash)

          item.except("text").map { |key, value| "#{key}: #{value}" }.join(", ")
        end
        parts << data_parts.join("; ") if data_parts.any?
      end

      "- #{date}: #{parts.compact_blank.join(' — ')}"
    end

    lines.join("\n")
  end

  def self.latest_source_updated_at(person)
    person.entries.maximum(:updated_at)&.utc
  end

  def self.broadcast_context_preview(chat, content)
    Turbo::StreamsChannel.broadcast_replace_to(
      "person_chat_#{chat.person_id}",
      target: "chat_context_preview",
      partial: "dashboard/chat_context_preview",
      locals: { context_preview: content }
    )
  end
end
