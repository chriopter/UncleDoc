class AddOccurredAtToEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :entries, :occurred_at, :datetime

    # Migrate existing entries: copy date to occurred_at
    execute <<-SQL.squish
      UPDATE entries
      SET occurred_at = datetime(date || ' 00:00:00')
      WHERE occurred_at IS NULL
    SQL
  end

  def down
    remove_column :entries, :occurred_at
  end
end
