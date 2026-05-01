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

      Cockpit rules:
      - You are inside the combined UncleDoc Cockpit for asking questions, adding notes, and uploading documents.
      - If the latest user message contains new health data, asks you to save/log something, or includes attached documents, call the `record_health_entry` tool before answering.
      - Appointments, open goals, and open tasks are part of the patient record. Use them when interpreting new entries and when answering follow-up questions.
      - Goals and tasks are stored as `todo` facts. If a saved activity supports or conflicts with an open goal, mention that relationship briefly after the tool returns.
      - Do not invent database fields yourself. The tool creates health entries and runs UncleDoc's parser. Multiple attached files are saved as separate document entries.
      - After the tool returns, briefly say what was saved or parsed, mention important extracted facts, and invite a follow-up question when useful.
      - If the user is only asking a question about existing data, answer from the patient record without calling the tool.
      - If the message is too ambiguous to know whether it should be saved, ask one short clarifying question instead of calling the tool.
    PROMPT
  end

  def self.patient_record_snapshot(person, entries)
    return I18n.t("chat.empty_record", name: person.name) if entries.empty?

    [
      planning_snapshot(entries),
      history_snapshot(entries)
    ].compact_blank.join("\n\n")
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

  def self.planning_snapshot(entries)
    upcoming_appointments = entries.select(&:appointment?).select { |entry| entry.appointment_calendar_time >= Time.zone.now.beginning_of_day }.sort_by { |entry| [ entry.appointment_calendar_time, entry.created_at ] }
    open_todos = entries.select(&:todo_open?).sort_by { |entry| [ todo_goal_sort_rank(entry), entry.display_time || Time.zone.at(0), entry.created_at ] }
    done_todos = entries.select { |entry| entry.todo? && entry.todo_done? }.sort_by { |entry| entry.todo_done_at || entry.updated_at || entry.created_at }.last(10).reverse

    sections = []
    sections << section_lines("Upcoming appointments", upcoming_appointments) { |entry| appointment_snapshot_line(entry) }
    sections << section_lines("Open goals & tasks", open_todos) { |entry| todo_snapshot_line(entry) }
    sections << section_lines("Recently completed goals & tasks", done_todos) { |entry| todo_snapshot_line(entry) }
    sections.compact_blank.join("\n\n")
  end

  def self.history_snapshot(entries)
    lines = entries.map { |entry| history_snapshot_line(entry) }
    section_lines("Health timeline", lines, &:itself)
  end

  def self.section_lines(title, items)
    return if items.blank?

    ([ "## #{title}" ] + items.map { |item| "- #{yield(item)}" }).join("\n")
  end

  def self.appointment_snapshot_line(entry)
    date = I18n.l(entry.appointment_calendar_time, format: :long)
    title = entry.appointment_title.presence || entry.fact_summary.presence || entry.input.presence
    details = fact_attribute_summary(entry.appointment_data, except: %w[text kind value scheduled_for])
    [ date, title, details ].compact_blank.join(" — ")
  end

  def self.todo_snapshot_line(entry)
    date = entry.display_time ? I18n.l(entry.display_time, format: :long) : I18n.t("chat.unknown_date")
    title = entry.todo_title.presence || entry.fact_summary.presence || entry.input.presence
    status = entry.todo_done? ? "done" : "open"
    details = fact_attribute_summary(entry.todo_data, except: %w[text kind value])
    [ "#{status}, #{date}", title, details ].compact_blank.join(" — ")
  end

  def self.history_snapshot_line(entry)
    date = entry.occurred_at ? I18n.l(entry.occurred_at, format: :long) : I18n.t("chat.unknown_date")
    parts = []
    parts << entry.fact_summary if entry.fact_items.present?
    parts << entry.input if entry.input.present?

    data_parts = entry.fact_objects.filter_map do |item|
      next unless item.is_a?(Hash)

      fact_attribute_summary(item, except: %w[text])
    end
    parts << data_parts.join("; ") if data_parts.any?

    "#{date}: #{parts.compact_blank.join(' — ')}"
  end

  def self.fact_attribute_summary(fact, except: [])
    fact.except(*except).map { |key, value| "#{key}: #{value}" }.join(", ")
  end

  def self.todo_goal_sort_rank(entry)
    entry.todo_data["quality"] == "goal" ? 0 : 1
  end
end
