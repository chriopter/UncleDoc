class HealthkitSummarySyncService
  Result = Struct.new(:created_count, :updated_count, :deleted_count, :enqueued_count, keyword_init: true)

  def self.call(person:, today: Time.zone.today)
    new(person:, today:).call
  end

  def initialize(person:, today: Time.zone.today)
    @person = person
    @today = today.to_date
  end

  def call
    previews = HealthkitSummaryPreviewer.call(person: @person, today: @today)
    existing_entries = @person.entries.where(source: Entry::SOURCES[:healthkit]).index_by(&:source_ref)

    created_count = 0
    updated_count = 0
    enqueued_count = 0

    Entry.transaction do
      previews.each do |preview|
        existing_entry = existing_entries.delete(preview.source_ref)

        entry = existing_entry || @person.entries.build(source: Entry::SOURCES[:healthkit], source_ref: preview.source_ref)
        changed = assign_preview(entry, preview)

        if entry.new_record?
          created_count += 1
          entry.save!
        elsif changed
          updated_count += 1
          entry.save!
        end

        if entry.previous_changes.present? && entry.pending_parse?
          EntryDataParseJob.perform_later(entry.id)
          enqueued_count += 1
        end
      end

      deleted_entries = existing_entries.values
      @deleted_count = deleted_entries.size
      deleted_entries.each(&:destroy!)
    end

    Result.new(
      created_count: created_count,
      updated_count: updated_count,
      deleted_count: @deleted_count || 0,
      enqueued_count: enqueued_count
    )
  end

  private

  def assign_preview(entry, preview)
    changed = false
    changed = assign_if_changed(entry, :source, Entry::SOURCES[:healthkit]) || changed
    changed = assign_if_changed(entry, :source_ref, preview.source_ref) || changed
    changed = assign_if_changed(entry, :input, preview.input) || changed
    changed = assign_if_changed(entry, :occurred_at, preview.occurred_at) || changed

    return false unless changed || entry.new_record?

    entry.facts = [] if entry.has_attribute?(:facts)
    entry.parseable_data = []
    entry.llm_response = {} if entry.has_attribute?(:llm_response)
    entry.todo_done = false if entry.has_attribute?(:todo_done)
    entry.todo_done_at = nil if entry.has_attribute?(:todo_done_at)
    entry.parse_status = EntryDataParser.ready? ? "pending" : "skipped" if entry.has_attribute?(:parse_status)
    true
  end

  def assign_if_changed(entry, attribute, value)
    current = entry.public_send(attribute)
    return false if current == value

    entry.public_send("#{attribute}=", value)
    true
  end
end
