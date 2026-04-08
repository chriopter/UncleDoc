class EntryReparseScheduler
  EMPTY_EXTRACTED_DATA = { "facts" => [], "document" => {}, "llm" => {} }.freeze

  Result = Struct.new(:marked_count, :scheduled, keyword_init: true)

  def self.call(scope:, batch_size:, max_pending:, delay_seconds:, source: nil)
    new(scope:, batch_size:, max_pending:, delay_seconds:, source:).call
  end

  def initialize(scope:, batch_size:, max_pending:, delay_seconds:, source: nil)
    @scope = scope
    @batch_size = batch_size
    @max_pending = max_pending
    @delay_seconds = delay_seconds
    @source = source
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
      source: @source
    )

    Result.new(marked_count:, scheduled: true)
  end

  private

  def mark_entries_pending
    count = 0

    pending_scope.find_each do |entry|
      entry.update!(extracted_data: EMPTY_EXTRACTED_DATA, parse_status: "pending")
      count += 1
    end

    count
  end

  def pending_scope
    @scope.where.not(source: Entry::SOURCES[:babywidget])
  end
end
