class CreateHealthkitSyncs < ActiveRecord::Migration[8.0]
  def change
    create_table :healthkit_syncs do |t|
      t.references :person, null: false, foreign_key: true
      t.string :device_id, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :last_synced_at
      t.datetime :last_successful_sync_at
      t.integer :synced_record_count, null: false, default: 0
      t.text :last_error
      t.json :details, null: false, default: {}

      t.timestamps
    end

    add_index :healthkit_syncs, [ :person_id, :device_id ], unique: true
  end
end
