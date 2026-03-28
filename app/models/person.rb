class Person < ApplicationRecord
  validates :name, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
