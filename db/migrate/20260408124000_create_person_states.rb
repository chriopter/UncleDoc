class CreatePersonStates < ActiveRecord::Migration[8.1]
  class MigrationPerson < ApplicationRecord
    self.table_name = "people"
  end

  class MigrationPersonState < ApplicationRecord
    self.table_name = "person_states"
  end

  def up
    create_table :person_states do |t|
      t.references :person, null: false, foreign_key: true, index: { unique: true }
      t.string :baby_feeding_timer_side
      t.datetime :baby_feeding_timer_started_at
      t.datetime :baby_sleep_timer_started_at

      t.timestamps
    end

    MigrationPerson.reset_column_information
    MigrationPersonState.reset_column_information

    MigrationPerson.find_each do |person|
      next unless person.baby_feeding_timer_side.present? || person.baby_feeding_timer_started_at.present? || person.baby_sleep_timer_started_at.present?

      MigrationPersonState.create!(
        person_id: person.id,
        baby_feeding_timer_side: person.baby_feeding_timer_side,
        baby_feeding_timer_started_at: person.baby_feeding_timer_started_at,
        baby_sleep_timer_started_at: person.baby_sleep_timer_started_at
      )
    end
  end

  def down
    drop_table :person_states
  end
end
