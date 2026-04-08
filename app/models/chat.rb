class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :person

  validates :person_id, uniqueness: true

  def visible_messages
    messages.where(hidden: false).order(:created_at, :id)
  end

  def context_message
    messages.where(message_kind: "context").order(:id).first
  end
end
