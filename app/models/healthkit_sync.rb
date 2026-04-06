class HealthkitSync < ApplicationRecord
  STATUSES = %w[pending syncing synced failed].freeze

  belongs_to :person

  validates :device_id, presence: true
  validates :status, inclusion: { in: STATUSES }
end
