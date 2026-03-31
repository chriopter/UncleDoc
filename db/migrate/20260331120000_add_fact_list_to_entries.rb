class AddFactListToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :fact_list, :json, default: [], null: false
  end
end
