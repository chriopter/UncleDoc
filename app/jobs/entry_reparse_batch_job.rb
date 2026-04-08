class EntryReparseBatchJob < ApplicationJob
  queue_as :default

  DEFAULT_BATCH_SIZE = 25
  DEFAULT_MAX_PENDING = 50
  DEFAULT_DELAY = 30.seconds

  def perform(cursor_id: 0, batch_size: DEFAULT_BATCH_SIZE, max_pending: DEFAULT_MAX_PENDING, delay_seconds: DEFAULT_DELAY.to_i, source: nil)
    return unless EntryDataParser.ready?

    pending_count = Entry.where(parse_status: "pending").count
    available_slots = max_pending.to_i - pending_count

    if available_slots <= 0
      self.class.set(wait: delay_seconds.to_i.seconds).perform_later(cursor_id:, batch_size:, max_pending:, delay_seconds:, source:)
      return
    end

    limit = [ batch_size.to_i, available_slots ].min
    entries = next_entries(cursor_id:, source:, limit:)
    return if entries.empty?

    last_id = nil

    entries.each do |entry|
      entry.update!(extracted_data: { "facts" => [], "document" => {}, "llm" => {} }, parse_status: "pending")
      EntryDataParseJob.perform_later(entry.id)
      last_id = entry.id
    end

    if last_id && more_entries_after?(last_id, source:)
      self.class.set(wait: delay_seconds.to_i.seconds).perform_later(cursor_id: last_id, batch_size:, max_pending:, delay_seconds:, source:)
    end
  end

  private

  def next_entries(cursor_id:, source:, limit:)
    scope = Entry.where("id > ?", cursor_id).where.not(source: Entry::SOURCES[:babywidget]).where.not(parse_status: "pending")
    scope = scope.where(source:) if source.present?
    scope.order(:id).limit(limit)
  end

  def more_entries_after?(cursor_id, source:)
    scope = Entry.where("id > ?", cursor_id).where.not(source: Entry::SOURCES[:babywidget]).where.not(parse_status: "pending")
    scope = scope.where(source:) if source.present?
    scope.exists?
  end
end
