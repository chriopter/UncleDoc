class LlmModel < ApplicationRecord
  self.table_name = "llm_models"

  acts_as_model chats: :llm_chats, chat_class: "LlmChat"
end
