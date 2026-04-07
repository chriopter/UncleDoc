class ClearHealthkitRecordsOnce < ActiveRecord::Migration[8.0]
  def up
    say "Skipping legacy HealthKit cleanup migration to preserve existing data", true
  end

  def down
    # no-op
  end
end
