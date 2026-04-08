namespace :files do
  desc "Backfill cached thumbnails for existing document entries"
  task backfill_thumbnails: :environment do
    scope = Entry.with_documents.includes(documents_attachments: :blob).order(:id)

    if ENV["PERSON_UUID"].present?
      person = Person.find_by!(uuid: ENV["PERSON_UUID"])
      scope = scope.where(person_id: person.id)
    elsif ENV["PERSON_NAME"].present?
      matches = Person.where(name: ENV["PERSON_NAME"])
      raise "PERSON_NAME matches multiple people; use PERSON_UUID" if matches.count > 1

      person = matches.first || raise(ActiveRecord::RecordNotFound)
      scope = scope.where(person_id: person.id)
    end

    scope = scope.where("entries.id >= ?", ENV["START_ID"].to_i) if ENV["START_ID"].present?
    scope = scope.limit(ENV["LIMIT"].to_i) if ENV["LIMIT"].present?

    queued = 0
    skipped = 0

    scope.find_each do |entry|
      document = entry.documents.first

      if document&.representable?
        DocumentThumbnailWarmJob.perform_later(entry.id)
        queued += 1
      else
        skipped += 1
      end
    end

    puts "Queued thumbnail warm jobs: #{queued}"
    puts "Skipped non-representable documents: #{skipped}"
  end
end
