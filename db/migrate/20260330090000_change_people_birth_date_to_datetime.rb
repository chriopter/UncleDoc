class ChangePeopleBirthDateToDatetime < ActiveRecord::Migration[8.1]
  def up
    add_column :people, :birth_at, :datetime

    execute <<~SQL
      UPDATE people
      SET birth_at = CASE
        WHEN birth_date IS NOT NULL THEN datetime(birth_date || ' 12:00:00')
        ELSE NULL
      END
    SQL

    remove_column :people, :birth_date, :date
    rename_column :people, :birth_at, :birth_date
  end

  def down
    add_column :people, :birth_on, :date

    execute <<~SQL
      UPDATE people
      SET birth_on = CASE
        WHEN birth_date IS NOT NULL THEN date(birth_date)
        ELSE NULL
      END
    SQL

    remove_column :people, :birth_date, :datetime
    rename_column :people, :birth_on, :birth_date
  end
end
