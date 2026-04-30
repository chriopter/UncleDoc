class EntryReparseScheduler
  EMPTY_EXTRACTED_DATA = { "facts" => [], "document" => {}, "llm" => {} }.freeze

  Result = Struct.new(:marked_count, :scheduled, keyword_init: true)

  def self.call(scope:, batch_size:, max_pending:, delay_seconds:, source: nil, person_id: nil, documents_only: false)
    new(scope:, batch_size:, max_pending:, delay_seconds:, source:, person_id:, documents_only:).call
  end

  def initialize(scope:, batch_size:, max_pending:, delay_seconds:, source: nil, person_id: nil, documents_only: false)
    @scope = scope
    @batch_size = batch_size
    @max_pending = max_pending
    @delay_seconds = delay_seconds
    @source = source
    @person_id = person_id
    @documents_only = documents_only
  end

  def call
    return Result.new(marked_count: 0, scheduled: false) unless EntryDataParser.ready?

    marked_count = mark_entries_pending
    return Result.new(marked_count:, scheduled: false) if marked_count.zero?

    first_id = pending_scope.order(:id).pick(:id)
    return Result.new(marked_count:, scheduled: false) unless first_id

    EntryReparseBatchJob.perform_later(
      cursor_id: first_id - 1,
      batch_size: @batch_size,
      max_pending: @max_pending,
      delay_seconds: @delay_seconds,
      source: @source,
      person_id: @person_id,
      documents_only: @documents_only
    )

    Result.new(marked_count:, scheduled: true)
  end

  private

  def mark_entries_pending
    scope = pending_scope.where.not(parse_status: "pending")
    ids = scope.ids
    return 0 if ids.empty?

    Entry.where(id: ids).update_all(extracted_data: EMPTY_EXTRACTED_DATA, parse_status: "pending", updated_at: Time.current)
    ids.size
  end

  def pending_scope
    @scope.where.not(source: Entry::SOURCES[:babywidget])
  end
end
