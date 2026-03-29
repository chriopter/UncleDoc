class EntryDataParseJob < ApplicationJob
  queue_as :default

  def perform(entry_id)
    entry = Entry.find_by(id: entry_id)
    return unless entry
    return if entry.parsed? && entry.data.present?

    result = EntryDataParser.call(note: entry.note, preference: UserPreference.current, entry: entry)
    if result.error.present?
      entry.update!(parse_status: "failed") if entry.pending_parse?
      broadcast_entries(entry.person)
      return
    end

    if entry.reload.pending_parse?
      entry.update!(data: result.data, parse_status: "parsed")
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
      target: "overview_person_meta",
      partial: "shared/overview_person_meta",
      locals: { person: person, entries: person.entries.recent_first }
    )
  end
end
