class Entry < ApplicationRecord
  belongs_to :person

  PARSE_STATUSES = %w[pending parsed failed].freeze

  validates :note, presence: true
  validates :occurred_at, presence: true
  validates :parse_status, inclusion: { in: PARSE_STATUSES }, if: -> { has_attribute?(:parse_status) }
  validate :data_must_be_array

  after_initialize :normalize_defaults

  scope :recent_first, -> { order(occurred_at: :desc, created_at: :desc) }
  scope :by_data_type, ->(type) {
    where("EXISTS (SELECT 1 FROM json_each(entries.data) WHERE json_extract(value, '$.type') = ?)", type)
  }

  def data_of_type(type)
    data_items.select { |item| item["type"] == type }
  end

  def first_data_of_type(type)
    data_of_type(type).first
  end

  def breast_feeding?
    data_of_type("breast_feeding").any?
  end

  def bottle_feeding?
    data_of_type("bottle_feeding").any?
  end

  def diaper?
    data_of_type("diaper").any?
  end

  def feeding?
    breast_feeding? || bottle_feeding?
  end

  def feeding_duration_minutes
    feeding = first_data_of_type("breast_feeding")
    numeric_value(feeding&.dig("value"))
  end

  def bottle_amount_ml
    bottle = first_data_of_type("bottle_feeding")
    numeric_value(bottle&.dig("value"))
  end

  def diaper_data
    first_data_of_type("diaper") || {}
  end

  def diaper_rash?
    diaper_data["rash"] == true
  end

  def diaper_wet?
    diaper_data["wet"] == true
  end

  def diaper_solid?
    diaper_data["solid"] == true
  end

  def display_time
    occurred_at || created_at
  end

  def pending_parse?
    current_parse_status == "pending"
  end

  def parsed?
    current_parse_status == "parsed"
  end

  def failed_parse?
    current_parse_status == "failed"
  end

  def time_since
    return nil unless display_time

    Time.current - display_time
  end

  private

  def normalize_defaults
    self.data = [] if data.nil?
    self.occurred_at ||= Time.current
    self.parse_status ||= data.present? ? "parsed" : "pending" if has_attribute?(:parse_status)
  end

  def current_parse_status
    return parse_status if has_attribute?(:parse_status)

    data.present? ? "parsed" : "pending"
  end

  def data_items
    data.is_a?(Array) ? data : []
  end

  def data_must_be_array
    return if data.is_a?(Array)

    errors.add(:data, :invalid)
  end

  def numeric_value(value)
    return value if value.is_a?(Numeric)
    return value.to_i if value.to_s.match?(/\A-?\d+\z/)
    return value.to_f if value.to_s.match?(/\A-?\d+\.\d+\z/)

    nil
  end
end
