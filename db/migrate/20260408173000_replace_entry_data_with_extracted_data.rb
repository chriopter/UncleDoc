class ReplaceEntryDataWithExtractedData < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :extracted_data, :json, null: false, default: { facts: [], llm: {} }

    remove_column :entries, :facts, :json, default: [], null: false
    remove_column :entries, :parseable_data, :json, default: [], null: false
    remove_column :entries, :llm_response, :json, default: {}, null: false
  end
end
