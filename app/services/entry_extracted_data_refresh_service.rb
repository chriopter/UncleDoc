class EntryExtractedDataRefreshService
  Result = Struct.new(:rebuilt_count, :queued_count, :scheduled, keyword_init: true)

  def self.call(batch_size: EntryReparseBatchJob::DEFAULT_BATCH_SIZE, max_pending: EntryReparseBatchJob::DEFAULT_MAX_PENDING, delay_seconds: EntryReparseBatchJob::DEFAULT_DELAY.to_i)
    new(batch_size:, max_pending:, delay_seconds:).call
  end

  def initialize(batch_size:, max_pending:, delay_seconds:)
    @batch_size = batch_size
    @max_pending = max_pending
    @delay_seconds = delay_seconds
  end

  def call
    rebuilt_count = rebuild_babywidget_entries
    scheduled = schedule_non_babywidget_reparse

    Result.new(
      rebuilt_count: rebuilt_count,
      queued_count: scheduled ? [ @batch_size.to_i, [ @max_pending.to_i - Entry.where(parse_status: "pending").count, 0 ].max ].min : 0,
      scheduled: scheduled
    )
  end

  private

  def rebuild_babywidget_entries
    rebuilt_count = 0

    Entry.babywidget_generated.find_each do |entry|
      facts = babywidget_facts_for(entry)
      next if facts.blank?

      entry.update!(extracted_data: { "facts" => facts, "document" => {}, "llm" => {} }, parse_status: "parsed")
      rebuilt_count += 1
    end

    rebuilt_count
  end

  def schedule_non_babywidget_reparse
    return false unless EntryDataParser.ready?
    return false unless Entry.where.not(source: Entry::SOURCES[:babywidget]).where.not(parse_status: "pending").exists?

    EntryReparseBatchJob.perform_later(batch_size: @batch_size, max_pending: @max_pending, delay_seconds: @delay_seconds)
    true
  end

  def babywidget_facts_for(entry)
    case entry.input.to_s.strip
    when /\ABottle (?<amount>\d+)ml\z/, /\AFlasche (?<amount>\d+)ml\z/
      EntryFactListBuilder.fact_objects([ { "type" => "bottle_feeding", "value" => Regexp.last_match[:amount].to_i, "unit" => "ml" } ])
    when /\ABreastfeeding (?<side>Left|Right), (?<duration>\d+) minutes\z/i, /\AStillen (?<side>Links|Rechts), (?<duration>\d+) Minuten\z/
      side = Regexp.last_match[:side].to_s.downcase.start_with?("r") ? "right" : "left"
      EntryFactListBuilder.fact_objects([ { "type" => "breast_feeding", "value" => Regexp.last_match[:duration].to_i, "unit" => "min", "side" => side } ])
    when /\ASleep (?<duration>\d+) min\z/, /\ASchlaf (?<duration>\d+) Min\z/
      EntryFactListBuilder.fact_objects([ { "type" => "sleep", "value" => Regexp.last_match[:duration].to_i, "unit" => "min" } ])
    when /\ADiaper: wet and solid\z/, /\AWindel: nass und fest\z/
      EntryFactListBuilder.fact_objects([ { "type" => "diaper", "wet" => true, "solid" => true } ])
    when /\ADiaper: wet\z/, /\AWindel: nass\z/
      EntryFactListBuilder.fact_objects([ { "type" => "diaper", "wet" => true, "solid" => false } ])
    when /\ADiaper: solid\z/, /\AWindel: fest\z/
      EntryFactListBuilder.fact_objects([ { "type" => "diaper", "wet" => false, "solid" => true } ])
    else
      []
    end
  end
end
