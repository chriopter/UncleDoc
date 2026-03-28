class Person < ApplicationRecord
  has_many :entries, dependent: :destroy

  validates :name, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
