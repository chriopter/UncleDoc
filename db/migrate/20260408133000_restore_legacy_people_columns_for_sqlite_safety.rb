class RestoreLegacyPeopleColumnsForSqliteSafety < ActiveRecord::Migration[8.1]
  def up
    add_column :people, :baby_feeding_timer_side, :string unless column_exists?(:people, :baby_feeding_timer_side)
    add_column :people, :baby_feeding_timer_started_at, :datetime unless column_exists?(:people, :baby_feeding_timer_started_at)
    add_column :people, :baby_sleep_timer_started_at, :datetime unless column_exists?(:people, :baby_sleep_timer_started_at)
    add_column :people, :locale, :string unless column_exists?(:people, :locale)
    add_column :people, :date_format, :string unless column_exists?(:people, :date_format)
  end

  def down
    # Keep these compatibility columns in place. They are harmless and help avoid
    # destructive SQLite table rebuilds in live deployments.
  end
end
