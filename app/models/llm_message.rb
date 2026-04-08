class LlmMessage < ApplicationRecord
  self.table_name = "llm_messages"

  acts_as_message chat: :llm_chat,
                  chat_class: "LlmChat",
                  tool_calls: :llm_tool_calls,
                  tool_call_class: "LlmToolCall",
                  model: :llm_model,
                  model_class: "LlmModel"
  has_many_attached :attachments

  after_create_commit :broadcast_created_message, unless: :skip_broadcast?
  after_update_commit :broadcast_updated_message, unless: :hidden?

  scope :visible, -> { where(hidden: false) }

  def broadcast_append_chunk(content)
    broadcast_append_to stream_name,
      target: "#{dom_id}_content",
      content: ERB::Util.html_escape(content.to_s)
  end

  private

  def broadcast_created_message
    broadcast_append_to stream_name,
      target: "chat_messages",
      partial: to_partial_path,
      locals: { message: self }
  end

  def broadcast_updated_message
    broadcast_replace_to stream_name,
      target: dom_id,
      partial: to_partial_path,
      locals: { message: self }
  end

  def skip_broadcast?
    hidden? || role == "user"
  end

  def stream_name
    "person_chat_#{llm_chat.person_id}"
  end

  def dom_id
    ActionView::RecordIdentifier.dom_id(self)
  end
end
