class AddMetadataToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :metadata, :jsonb, default: {}
    add_index :entries, :metadata, using: :gin
  end
end
