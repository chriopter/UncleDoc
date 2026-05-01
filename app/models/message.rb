class Message < ApplicationRecord
  attr_accessor :suppress_broadcast

  acts_as_message
  has_many_attached :attachments

  after_create_commit :broadcast_created_message, unless: :skip_broadcast?
  after_update_commit :broadcast_updated_message, unless: :hidden?

  scope :visible, -> { where(hidden: false) }

  def broadcast_streaming_content(content)
    broadcast_update_to stream_name,
      target: "#{dom_id}_raw_content",
      content: ERB::Util.html_escape(content.to_s)
  end

  def skip_broadcast?
    suppress_broadcast || hidden? || role == "user"
  end

  def streaming_placeholder?
    message_kind == "streaming"
  end

  private

  def broadcast_created_message
    broadcast_replace_to stream_name,
      target: "chat_timeline",
      partial: "dashboard/chat_timeline",
      locals: { person: chat.person, chat: chat }
  end

  def broadcast_updated_message
    broadcast_replace_to stream_name,
      target: dom_id,
      partial: to_partial_path,
      locals: { message: self }
  end

  def stream_name
    "person_chat_#{chat.person_id}"
  end

  def dom_id
    ActionView::RecordIdentifier.dom_id(self)
  end
end
