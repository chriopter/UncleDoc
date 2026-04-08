class AddHealthkitRecordsPersonStartAtCreatedAtIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :healthkit_records,
      [ :person_id, :start_at, :created_at ],
      name: "index_healthkit_records_on_person_id_start_at_created_at",
      if_not_exists: true
  end
end
