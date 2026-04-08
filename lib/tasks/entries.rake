namespace :entries do
  desc "Rebuild babywidget extracted_data and safely schedule batched reparsing for other entries"
  task refresh_extracted_data: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", EntryReparseBatchJob::DEFAULT_BATCH_SIZE)
    max_pending = ENV.fetch("MAX_PENDING", EntryReparseBatchJob::DEFAULT_MAX_PENDING)
    delay_seconds = ENV.fetch("BATCH_DELAY", EntryReparseBatchJob::DEFAULT_DELAY.to_i)

    result = EntryExtractedDataRefreshService.call(batch_size:, max_pending:, delay_seconds:)

    puts "Rebuilt babywidget entries: #{result.rebuilt_count}"
    puts "Scheduled non-babywidget reparses: #{result.scheduled ? 'yes' : 'no'}"
    puts "Initial batch target: #{result.queued_count}"
    puts "Batch size: #{batch_size}"
    puts "Max pending: #{max_pending}"
    puts "Batch delay seconds: #{delay_seconds}"
  end
end
