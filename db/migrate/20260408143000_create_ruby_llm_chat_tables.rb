class CreateRubyLlmChatTables < ActiveRecord::Migration[8.1]
  def change
    create_table :models do |t|
      t.string :model_id, null: false
      t.string :name, null: false
      t.string :provider, null: false
      t.string :family
      t.datetime :model_created_at
      t.integer :context_window
      t.integer :max_output_tokens
      t.date :knowledge_cutoff
      t.json :modalities, default: {}
      t.json :capabilities, default: []
      t.json :pricing, default: {}
      t.json :metadata, default: {}
      t.timestamps

      t.index [ :provider, :model_id ], unique: true
      t.index :provider
      t.index :family
    end

    create_table :chats do |t|
      t.references :person, null: false, foreign_key: true, index: { unique: true }
      t.references :model, foreign_key: true
      t.datetime :context_refreshed_at
      t.datetime :context_source_updated_at
      t.timestamps
    end

    create_table :messages do |t|
      t.references :chat, null: false, foreign_key: true
      t.references :model, foreign_key: true
      t.references :tool_call, foreign_key: true
      t.string :role, null: false
      t.string :message_kind, null: false, default: "message"
      t.boolean :hidden, null: false, default: false
      t.text :content
      t.json :content_raw
      t.text :thinking_text
      t.text :thinking_signature
      t.integer :thinking_tokens
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cached_tokens
      t.integer :cache_creation_tokens
      t.timestamps

      t.index :role
      t.index :message_kind
    end

    create_table :tool_calls do |t|
      t.references :message, null: false, foreign_key: true
      t.string :tool_call_id, null: false
      t.string :name, null: false
      t.text :thought_signature
      t.json :arguments, default: {}
      t.timestamps

      t.index :tool_call_id, unique: true
      t.index :name
    end
  end
end
