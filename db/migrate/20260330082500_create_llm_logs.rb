class CreateLlmLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_logs do |t|
      t.references :person, foreign_key: true
      t.references :entry, foreign_key: true
      t.string :request_kind, null: false
      t.string :provider, null: false
      t.string :model
      t.string :endpoint, null: false
      t.integer :status_code
      t.text :request_payload, null: false
      t.text :response_body
      t.text :error_message

      t.timestamps
    end
  end
end
