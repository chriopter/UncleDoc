class RenameRubyLlmTables < ActiveRecord::Migration[8.1]
  def change
    rename_table :models, :llm_models
    rename_table :chats, :llm_chats
    rename_table :messages, :llm_messages
    rename_table :tool_calls, :llm_tool_calls

    rename_column :llm_chats, :model_id, :llm_model_id
    rename_column :llm_messages, :chat_id, :llm_chat_id
    rename_column :llm_messages, :model_id, :llm_model_id
    rename_column :llm_messages, :tool_call_id, :llm_tool_call_id
    rename_column :llm_tool_calls, :message_id, :llm_message_id

    rename_index :llm_models, "index_models_on_family", "index_llm_models_on_family"
    rename_index :llm_models, "index_models_on_provider", "index_llm_models_on_provider"
    rename_index :llm_models, "index_models_on_provider_and_model_id", "index_llm_models_on_provider_and_model_id"
    rename_index :llm_chats, "index_chats_on_model_id", "index_llm_chats_on_llm_model_id"
    rename_index :llm_chats, "index_chats_on_person_id", "index_llm_chats_on_person_id"
    rename_index :llm_messages, "index_messages_on_chat_id", "index_llm_messages_on_llm_chat_id"
    rename_index :llm_messages, "index_messages_on_model_id", "index_llm_messages_on_llm_model_id"
    rename_index :llm_messages, "index_messages_on_role", "index_llm_messages_on_role"
    rename_index :llm_messages, "index_messages_on_message_kind", "index_llm_messages_on_message_kind"
    rename_index :llm_messages, "index_messages_on_tool_call_id", "index_llm_messages_on_llm_tool_call_id"
    rename_index :llm_tool_calls, "index_tool_calls_on_message_id", "index_llm_tool_calls_on_llm_message_id"
    rename_index :llm_tool_calls, "index_tool_calls_on_name", "index_llm_tool_calls_on_name"
    rename_index :llm_tool_calls, "index_tool_calls_on_tool_call_id", "index_llm_tool_calls_on_tool_call_id"

    remove_foreign_key :llm_chats, column: :llm_model_id
    remove_foreign_key :llm_messages, column: :llm_chat_id
    remove_foreign_key :llm_messages, column: :llm_model_id
    remove_foreign_key :llm_messages, column: :llm_tool_call_id
    remove_foreign_key :llm_tool_calls, column: :llm_message_id

    add_foreign_key :llm_chats, :llm_models, column: :llm_model_id
    add_foreign_key :llm_messages, :llm_chats, column: :llm_chat_id
    add_foreign_key :llm_messages, :llm_models, column: :llm_model_id
    add_foreign_key :llm_messages, :llm_tool_calls, column: :llm_tool_call_id
    add_foreign_key :llm_tool_calls, :llm_messages, column: :llm_message_id
  end
end
