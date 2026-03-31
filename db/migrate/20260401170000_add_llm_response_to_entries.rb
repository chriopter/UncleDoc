class AddLlmResponseToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :llm_response, :json, default: {}, null: false
  end
end
