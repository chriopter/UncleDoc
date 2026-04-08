class DropLlmLogs < ActiveRecord::Migration[8.1]
  def change
    drop_table :llm_logs do |t|
      t.string :request_kind, null: false
      t.string :provider, null: false
      t.string :model
      t.string :endpoint, null: false
      t.text :request_payload, null: false
      t.text :response_body
      t.integer :status_code
      t.text :error_message
      t.references :person, foreign_key: { on_delete: :cascade }
      t.references :entry, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
  end
end
