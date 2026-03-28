class Entry < ApplicationRecord
  belongs_to :person

  validates :date, presence: true
  validates :note, presence: true

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }
end
