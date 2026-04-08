class HealthkitSummaryReparseJob < ApplicationJob
  queue_as :default

  def perform(person_id)
    person = Person.find_by(id: person_id)
    return unless person

    person.entries.where(source: Entry::SOURCES[:healthkit]).find_each do |entry|
      entry.update!(
        extracted_data: { "facts" => [], "llm" => {} },
        parse_status: EntryDataParser.ready? ? "pending" : "skipped"
      )

      EntryDataParseJob.perform_later(entry.id) if entry.pending_parse?
    end
  end
end
