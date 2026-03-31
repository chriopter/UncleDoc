class AddBabyTimersToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :baby_feeding_timer_started_at, :datetime
    add_column :people, :baby_feeding_timer_side, :string
    add_column :people, :baby_sleep_timer_started_at, :datetime
  end
end
