class EntryReparseBatchJob < ApplicationJob
  queue_as :default

  DEFAULT_BATCH_SIZE = 25
  DEFAULT_MAX_PENDING = 50
  DEFAULT_DELAY = 30.seconds

  def perform(cursor_id: 0, batch_size: DEFAULT_BATCH_SIZE, max_pending: DEFAULT_MAX_PENDING, delay_seconds: DEFAULT_DELAY.to_i, source: nil, person_id: nil, documents_only: false)
    return unless EntryDataParser.ready?

    queued_count = queued_parse_job_count
    available_slots = max_pending.to_i - queued_count

    if available_slots <= 0
      self.class.set(wait: delay_seconds.to_i.seconds).perform_later(cursor_id:, batch_size:, max_pending:, delay_seconds:, source:, person_id:, documents_only:)
      return
    end

    limit = [ batch_size.to_i, available_slots ].min
    entries = next_entries(cursor_id:, source:, person_id:, documents_only:, limit:)
    return if entries.empty?

    last_id = nil

    entries.each do |entry|
      EntryDataParseJob.perform_later(entry.id)
      last_id = entry.id
    end

    if last_id && more_entries_after?(last_id, source:, person_id:, documents_only:)
      self.class.set(wait: delay_seconds.to_i.seconds).perform_later(cursor_id: last_id, batch_size:, max_pending:, delay_seconds:, source:, person_id:, documents_only:)
    end
  end

  private

  def next_entries(cursor_id:, source:, person_id:, documents_only:, limit:)
    scope = pending_scope_after(cursor_id, source:, person_id:, documents_only:)
    scope.order(:id).limit(limit)
  end

  def more_entries_after?(cursor_id, source:, person_id:, documents_only:)
    pending_scope_after(cursor_id, source:, person_id:, documents_only:).exists?
  end

  def pending_scope_after(cursor_id, source:, person_id:, documents_only:)
    scope = Entry.where("entries.id > ?", cursor_id).where.not(source: Entry::SOURCES[:babywidget]).where(parse_status: "pending")
    scope = scope.where(source:) if source.present?
    scope = scope.where(person_id:) if person_id.present?
    scope = scope.joins(:documents_attachments).distinct if documents_only
    scope
  end

  def queued_parse_job_count
    ready = SolidQueue::ReadyExecution.joins(:job).where(solid_queue_jobs: { class_name: "EntryDataParseJob", queue_name: "parse" }).count
    claimed = SolidQueue::ClaimedExecution.joins(:job).where(solid_queue_jobs: { class_name: "EntryDataParseJob", queue_name: "parse" }).count
    ready + claimed
  rescue ActiveRecord::StatementInvalid
    0
  end
end
