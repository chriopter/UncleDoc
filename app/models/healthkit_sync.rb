class HealthkitSync < ApplicationRecord
  STATUSES = %w[pending syncing synced failed].freeze

  belongs_to :person

  validates :device_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  def effective_status
    return "failed" if status == "failed"
    return "synced" if last_successful_sync_at.present? && status == "syncing"

    status
  end
end
