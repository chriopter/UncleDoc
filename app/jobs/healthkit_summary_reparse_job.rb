class HealthkitSummaryReparseJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 15
  MAX_PENDING = 30
  DELAY_SECONDS = 20

  def perform(person_id)
    person = Person.find_by(id: person_id)
    return unless person

    EntryReparseScheduler.call(
      scope: person.entries.where(source: Entry::SOURCES[:healthkit]),
      batch_size: BATCH_SIZE,
      max_pending: MAX_PENDING,
      delay_seconds: DELAY_SECONDS,
      source: Entry::SOURCES[:healthkit]
    )
  end
end
