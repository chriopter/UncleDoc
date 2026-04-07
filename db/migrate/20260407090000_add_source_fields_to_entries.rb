class AddSourceFieldsToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :source, :string, null: false, default: "manual"
    add_column :entries, :source_ref, :string

    add_index :entries, [ :person_id, :source, :source_ref ],
      unique: true,
      where: "source_ref IS NOT NULL",
      name: "index_entries_on_person_source_and_source_ref"
  end
end
