class AddEntryTypeToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :entry_type, :string
  end
end
