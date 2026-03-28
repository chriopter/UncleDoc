class Person < ApplicationRecord
  has_many :entries, dependent: :destroy

  validates :name, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :baby_mode, -> { where(baby_mode: true) }

  def last_feeding
    entries.baby_feedings.recent_first.first
  end

  def last_diaper
    entries.baby_diapers.recent_first.first
  end

  def time_since_last_feeding
    last_feeding&.created_at
  end

  def time_since_last_diaper
    last_diaper&.created_at
  end
end
