class RevertRubyLlmTablesToDefaults < ActiveRecord::Migration[8.1]
  def up
    rename_table :llm_models, :models
    rename_table :llm_chats, :chats
    rename_table :llm_messages, :messages
    rename_table :llm_tool_calls, :tool_calls

    rename_column :chats, :llm_model_id, :model_id
    rename_column :messages, :llm_chat_id, :chat_id
    rename_column :messages, :llm_model_id, :model_id
    rename_column :messages, :llm_tool_call_id, :tool_call_id
    rename_column :tool_calls, :llm_message_id, :message_id

    rename_index :models, "index_llm_models_on_family", "index_models_on_family"
    rename_index :models, "index_llm_models_on_provider", "index_models_on_provider"
    rename_index :models, "index_llm_models_on_provider_and_model_id", "index_models_on_provider_and_model_id"
    rename_index :chats, "index_llm_chats_on_model_id", "index_chats_on_model_id"
    rename_index :chats, "index_llm_chats_on_person_id", "index_chats_on_person_id"
    rename_index :messages, "index_llm_messages_on_chat_id", "index_messages_on_chat_id"
    rename_index :messages, "index_llm_messages_on_model_id", "index_messages_on_model_id"
    rename_index :messages, "index_llm_messages_on_tool_call_id", "index_messages_on_tool_call_id"
    rename_index :messages, "index_llm_messages_on_message_kind", "index_messages_on_message_kind"
    rename_index :messages, "index_llm_messages_on_role", "index_messages_on_role"
    rename_index :tool_calls, "index_llm_tool_calls_on_message_id", "index_tool_calls_on_message_id"
    rename_index :tool_calls, "index_llm_tool_calls_on_name", "index_tool_calls_on_name"
    rename_index :tool_calls, "index_llm_tool_calls_on_tool_call_id", "index_tool_calls_on_tool_call_id"
  end

  def down
    rename_index :tool_calls, "index_tool_calls_on_tool_call_id", "index_llm_tool_calls_on_tool_call_id"
    rename_index :tool_calls, "index_tool_calls_on_name", "index_llm_tool_calls_on_name"
    rename_index :tool_calls, "index_tool_calls_on_message_id", "index_llm_tool_calls_on_message_id"
    rename_index :messages, "index_messages_on_role", "index_llm_messages_on_role"
    rename_index :messages, "index_messages_on_message_kind", "index_llm_messages_on_message_kind"
    rename_index :messages, "index_messages_on_tool_call_id", "index_llm_messages_on_tool_call_id"
    rename_index :messages, "index_messages_on_model_id", "index_llm_messages_on_model_id"
    rename_index :messages, "index_messages_on_chat_id", "index_llm_messages_on_chat_id"
    rename_index :chats, "index_chats_on_person_id", "index_llm_chats_on_person_id"
    rename_index :chats, "index_chats_on_model_id", "index_llm_chats_on_model_id"
    rename_index :models, "index_models_on_provider_and_model_id", "index_llm_models_on_provider_and_model_id"
    rename_index :models, "index_models_on_provider", "index_llm_models_on_provider"
    rename_index :models, "index_models_on_family", "index_llm_models_on_family"

    rename_column :tool_calls, :message_id, :llm_message_id
    rename_column :messages, :tool_call_id, :llm_tool_call_id
    rename_column :messages, :model_id, :llm_model_id
    rename_column :messages, :chat_id, :llm_chat_id
    rename_column :chats, :model_id, :llm_model_id

    rename_table :tool_calls, :llm_tool_calls
    rename_table :messages, :llm_messages
    rename_table :chats, :llm_chats
    rename_table :models, :llm_models
  end
end
