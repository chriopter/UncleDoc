class Person < ApplicationRecord
  has_many :entries, dependent: :destroy

  validates :name, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :baby_mode, -> { where(baby_mode: true) }

  def last_feeding
    entries.where(
      "EXISTS (SELECT 1 FROM json_each(entries.data) WHERE json_extract(value, '$.type') IN ('breast_feeding', 'bottle_feeding'))"
    ).recent_first.first
  end

  def last_diaper
    entries.by_data_type("diaper").recent_first.first
  end

  def time_since_last_feeding
    last_feeding&.display_time
  end

  def time_since_last_diaper
    last_diaper&.display_time
  end
end
