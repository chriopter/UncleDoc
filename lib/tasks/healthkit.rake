namespace :healthkit do
  desc "Preview generated HealthKit summaries without saving"
  task preview_summaries: :environment do
    today = healthkit_task_today
    person = healthkit_task_person

    previews = HealthkitSummaryPreviewer.call(person:, today:)

    puts "Person: #{person.name} (#{person.uuid})"
    puts "Today: #{today}"
    puts "Preview count: #{previews.size}"
    puts

    previews.each do |preview|
      puts "[#{preview.period_type}] #{preview.source_ref}"
      puts preview.input
      puts "Present record types: #{preview.present_record_types.join(', ')}"
      puts "Missing record types: #{preview.missing_record_types.join(', ')}"
      puts
    end
  end

  desc "Generate or refresh HealthKit summary entries"
  task sync_summaries: :environment do
    today = healthkit_task_today
    people = if ENV["PERSON_UUID"].present? || ENV["PERSON_NAME"].present?
      [ healthkit_task_person ]
    else
      Person.joins(:healthkit_records).distinct.order(:name)
    end

    people.each do |person|
      result = HealthkitSummarySyncService.call(person:, today:)
      puts "#{person.name} (#{person.uuid})"
      puts "  created: #{result.created_count}"
      puts "  updated: #{result.updated_count}"
      puts "  deleted: #{result.deleted_count}"
      puts "  enqueued: #{result.enqueued_count}"
    end
  end

  desc "Requeue parsing for generated HealthKit summary entries"
  task reparse_summaries: :environment do
    people = if ENV["PERSON_UUID"].present? || ENV["PERSON_NAME"].present?
      [ healthkit_task_person ]
    else
      Person.joins(:entries).where(entries: { source: Entry::SOURCES[:healthkit] }).distinct.order(:name)
    end

    people.each do |person|
      count = 0

      person.entries.where(source: Entry::SOURCES[:healthkit]).find_each do |entry|
        entry.update!(facts: [], parseable_data: [], llm_response: {}, parse_status: EntryDataParser.ready? ? "pending" : "skipped")
        if entry.pending_parse?
          EntryDataParseJob.perform_later(entry.id)
          count += 1
        end
      end

      puts "#{person.name} (#{person.uuid})"
      puts "  reparsed: #{count}"
    end
  end

  def healthkit_task_today
    Date.iso8601(ENV["TODAY"])
  rescue ArgumentError, TypeError
    Time.zone.today
  end

  def healthkit_task_person
    if ENV["PERSON_UUID"].present?
      Person.find_by!(uuid: ENV["PERSON_UUID"])
    elsif ENV["PERSON_NAME"].present?
      matches = Person.where(name: ENV["PERSON_NAME"])
      raise "PERSON_NAME matches multiple people; use PERSON_UUID" if matches.count > 1

      matches.first || raise(ActiveRecord::RecordNotFound)
    else
      people = Person.joins(:healthkit_records).distinct.order(:name)
      raise "Set PERSON_UUID or PERSON_NAME" unless people.one?

      people.first
    end
  end
end
