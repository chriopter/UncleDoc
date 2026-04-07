namespace :healthkit do
  desc "Preview generated HealthKit summaries without saving"
  task preview_summaries: :environment do
    today = begin
      Date.iso8601(ENV["TODAY"])
    rescue ArgumentError, TypeError
      Time.zone.today
    end

    person = if ENV["PERSON_UUID"].present?
      Person.find_by!(uuid: ENV["PERSON_UUID"])
    elsif ENV["PERSON_NAME"].present?
      Person.find_by!(name: ENV["PERSON_NAME"])
    else
      people = Person.joins(:healthkit_records).distinct.order(:name)
      raise "Set PERSON_UUID or PERSON_NAME" unless people.one?

      people.first
    end

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
end
