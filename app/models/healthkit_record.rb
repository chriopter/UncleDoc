class HealthkitRecord < ApplicationRecord
  belongs_to :person

  validates :external_id, :record_type, :start_at, :device_id, presence: true

  scope :recent_first, -> { order(start_at: :desc, created_at: :desc) }
end
