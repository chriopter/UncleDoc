class HealthkitSummaryReparseJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 15
  MAX_PENDING = 30
  DELAY_SECONDS = 20

  def perform(person_id)
    person = Person.find_by(id: person_id)
    return unless person
    return unless EntryDataParser.ready?

    first_healthkit_entry_id = person.entries.where(source: Entry::SOURCES[:healthkit]).order(:id).pick(:id)
    return unless first_healthkit_entry_id

    EntryReparseBatchJob.perform_later(
      cursor_id: first_healthkit_entry_id - 1,
      batch_size: BATCH_SIZE,
      max_pending: MAX_PENDING,
      delay_seconds: DELAY_SECONDS,
      source: Entry::SOURCES[:healthkit]
    )
  end
end
