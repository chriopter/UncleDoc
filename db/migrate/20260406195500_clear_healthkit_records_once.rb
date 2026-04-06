class ClearHealthkitRecordsOnce < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Clearing healthkit records and resetting sync counters" do
      execute("DELETE FROM healthkit_records")
      execute("UPDATE healthkit_syncs SET synced_record_count = 0, status = 'pending', last_successful_sync_at = NULL, last_error = NULL")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "healthkit_records cleanup cannot be reversed"
  end
end
