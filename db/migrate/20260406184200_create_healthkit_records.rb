class CreateHealthkitRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :healthkit_records do |t|
      t.references :person, null: false, foreign_key: true
      t.string :device_id, null: false
      t.string :external_id, null: false
      t.string :record_type, null: false
      t.string :source_name
      t.datetime :start_at, null: false
      t.datetime :end_at
      t.json :payload, null: false, default: {}

      t.timestamps
    end

    add_index :healthkit_records, [ :person_id, :external_id ], unique: true
    add_index :healthkit_records, [ :person_id, :record_type, :start_at ]
  end
end
