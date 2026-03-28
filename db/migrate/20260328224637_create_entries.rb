class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entries do |t|
      t.references :person, null: false, foreign_key: true
      t.date :date, null: false
      t.text :note, null: false

      t.timestamps
    end
  end
end
