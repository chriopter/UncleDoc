class EntryDataParseJob < ApplicationJob
  queue_as :parse

  def perform(entry_id)
    entry = Entry.find_by(id: entry_id)
    return unless entry
    return if entry.babywidget_generated?
    return if entry.parsed? && entry.fact_objects.present?

    result = EntryDataParser.call(input: entry.input, preference: AppSetting.current, entry: entry)
    if result.error.present?
      entry.update!(parse_status: "failed") if entry.pending_parse?
      broadcast_entries(entry.person)
      return
    end

    if entry.reload.pending_parse?
      attributes = { extracted_data: { "facts" => result.fact_objects, "document" => result.document, "llm" => result.llm }, parse_status: "parsed" }
      attributes[:occurred_at] = result.occurred_at if result.occurred_at.present?
      entry.update!(attributes)
      broadcast_entries(entry.person)
    end
  end

  private

  def broadcast_entries(person)
    partial = person.baby_mode? ? "entries/baby_list" : "entries/protocol_list"
    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "entries_list",
      partial: partial,
      locals: { entries: person.entries.recent_first }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_recent_activity",
      partial: "shared/overview_recent_activity",
      locals: { person: person, entries: person.entries.recent_first }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "files_list",
      partial: "dashboard/files_list",
      locals: { document_entries: person.entries.with_documents.recent_first }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "files_stats",
      partial: "dashboard/files_stats",
      locals: { document_entries: person.entries.with_documents.recent_first, document_count: person.entries.with_documents.sum(&:document_count) }
    )

    if person.baby_mode?
      Turbo::StreamsChannel.broadcast_replace_to(
        [ person, :entries ],
        target: "overview_baby_actions",
        partial: "shared/baby_actions_widget",
        locals: { person: person, card_classes: "h-full" }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        [ person, :entries ],
        target: "overview_baby_tracking_feeding",
        partial: "shared/baby_feeding_tracker_widget",
        locals: { person: person, card_classes: "flex-1" }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        [ person, :entries ],
        target: "overview_baby_tracking_sleep",
        partial: "shared/baby_sleep_tracker_widget",
        locals: { person: person, card_classes: "flex-1" }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        [ person, :entries ],
        target: "overview_baby_tracking_diaper",
        partial: "shared/baby_diaper_tracker_widget",
        locals: { person: person, card_classes: "flex-1" }
      )
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_planning",
      partial: "shared/planning_widget",
      locals: { person: person, card_classes: "h-full" }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_person_meta",
      partial: "shared/overview_person_meta",
      locals: { person: person, entries: person.entries.recent_first }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_weight_activity",
      partial: "shared/weight_activity_widget",
      locals: { person: person }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_height_activity",
      partial: "shared/height_activity_widget",
      locals: { person: person }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_temperature_activity",
      partial: "shared/vital_activity_widget",
      locals: { person: person, type: :temperature }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_pulse_activity",
      partial: "shared/vital_activity_widget",
      locals: { person: person, type: :pulse }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ person, :entries ],
      target: "overview_blood_pressure_activity",
      partial: "shared/vital_activity_widget",
      locals: { person: person, type: :blood_pressure }
    )
  end
end
