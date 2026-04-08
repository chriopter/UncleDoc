class LlmChat < ApplicationRecord
  self.table_name = "llm_chats"

  acts_as_chat messages: :llm_messages, message_class: "LlmMessage", model: :llm_model, model_class: "LlmModel"

  belongs_to :person

  validates :person_id, uniqueness: true

  def visible_messages
    llm_messages.where(hidden: false).order(:created_at, :id)
  end

  def context_message
    llm_messages.where(message_kind: "context").order(:id).first
  end
end
