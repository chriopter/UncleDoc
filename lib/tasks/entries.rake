namespace :entries do
  desc "Rebuild babywidget extracted_data and queue reparsing for all other entries"
  task refresh_extracted_data: :environment do
    result = EntryExtractedDataRefreshService.call

    puts "Rebuilt babywidget entries: #{result.rebuilt_count}"
    puts "Queued non-babywidget reparses: #{result.queued_count}"
  end
end
