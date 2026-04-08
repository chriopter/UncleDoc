class Entry < ApplicationRecord
  belongs_to :person
  has_many_attached :documents

  PARSE_STATUSES = %w[pending parsed failed skipped].freeze
  SOURCES = { manual: "manual", healthkit: "healthkit" }.freeze
  DOCUMENT_CONTENT_TYPES = %w[application/pdf image/png image/jpeg text/plain].freeze
  MAX_DOCUMENT_COUNT = 5
  MAX_DOCUMENT_SIZE = 10.megabytes

  validates :occurred_at, presence: true
  validates :parse_status, inclusion: { in: PARSE_STATUSES }, if: -> { has_attribute?(:parse_status) }
  validates :source, inclusion: { in: SOURCES.values }, if: -> { has_attribute?(:source) }
  validate :parseable_data_must_be_array
  validate :facts_must_be_array
  validate :llm_response_must_be_hash
  validate :input_or_documents_present
  validate :documents_are_supported

  after_initialize :normalize_defaults

  scope :recent_first, -> { order(occurred_at: :desc, created_at: :desc) }
  scope :entered_first, -> { order(created_at: :desc, occurred_at: :desc) }
  scope :with_documents, -> { includes(documents_attachments: :blob).where.associated(:documents_attachments).distinct }
  scope :by_parseable_data_type, ->(type) {
    where("EXISTS (SELECT 1 FROM json_each(entries.parseable_data) WHERE json_extract(value, '$.type') = ?)", type)
  }
  scope :healthkit_generated, -> { where(source: SOURCES[:healthkit]) }

  def parseable_data_of_type(type)
    parseable_data_items.select { |item| item["type"] == type }
  end

  def first_parseable_data_of_type(type)
    parseable_data_of_type(type).first
  end

  def breast_feeding?
    parseable_data_of_type("breast_feeding").any?
  end

  def bottle_feeding?
    parseable_data_of_type("bottle_feeding").any?
  end

  def diaper?
    parseable_data_of_type("diaper").any?
  end

  def sleep?
    parseable_data_of_type("sleep").any?
  end

  def appointment?
    parseable_data_of_type("appointment").any?
  end

  def todo?
    parseable_data_of_type("todo").any?
  end

  def feeding?
    breast_feeding? || bottle_feeding?
  end

  def feeding_duration_minutes
    feeding = first_parseable_data_of_type("breast_feeding")
    numeric_value(feeding&.dig("value"))
  end

  def feeding_side
    first_parseable_data_of_type("breast_feeding")&.dig("side")
  end

  def bottle_amount_ml
    bottle = first_parseable_data_of_type("bottle_feeding")
    numeric_value(bottle&.dig("value"))
  end

  def diaper_data
    first_parseable_data_of_type("diaper") || {}
  end

  def sleep_data
    first_parseable_data_of_type("sleep") || {}
  end

  def appointment_data
    first_parseable_data_of_type("appointment") || {}
  end

  def todo_data
    first_parseable_data_of_type("todo") || {}
  end

  def diaper_rash?
    diaper_data["rash"] == true
  end

  def sleep_duration_minutes
    numeric_value(sleep_data["value"])
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

  def fact_items
    facts.is_a?(Array) ? facts.filter_map { |item| item.to_s.strip.presence } : []
  end

  def fact_summary
    fact_items.join(". ")
  end

  def documents_attached?
    documents.attached?
  end

  def document_names
    documents.map { |document| document.filename.to_s }
  end

  def document_count
    documents.size
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

  def skipped_parse?
    current_parse_status == "skipped"
  end

  def todo_open?
    todo? && !todo_done?
  end

  def healthkit_generated?
    source == SOURCES[:healthkit]
  end

  def todo_title
    todo_data["value"].presence
  end

  def appointment_title
    appointment_data["value"].presence
  end

  def time_since
    return nil unless display_time

    Time.current - display_time
  end

  private

  def self.sorted_by(mode)
    mode.to_s == "entered" ? entered_first : recent_first
  end

  def normalize_defaults
    self[:parseable_data] = [] if has_attribute?(:parseable_data) && self[:parseable_data].nil?
    self[:facts] = [] if has_attribute?(:facts) && self[:facts].nil?
    self[:llm_response] = {} if has_attribute?(:llm_response) && self[:llm_response].nil?
    self.occurred_at ||= Time.current
    self.parse_status ||= parseable_data_value.present? ? "parsed" : "pending" if has_attribute?(:parse_status)
  end

  def current_parse_status
    return parse_status if has_attribute?(:parse_status)

    parseable_data_value.present? ? "parsed" : "pending"
  end

  def parseable_data_items
    parseable_data_value.is_a?(Array) ? parseable_data_value : []
  end

  def parseable_data_must_be_array
    return if parseable_data_value.is_a?(Array)

    errors.add(:parseable_data, :invalid)
  end

  def input_or_documents_present
    return if input.to_s.strip.present? || documents_attached?

    errors.add(:input, :blank)
  end

  def documents_are_supported
    return unless documents.attached?

    if documents.size > MAX_DOCUMENT_COUNT
      errors.add(:documents, I18n.t("entries.documents.errors.too_many", count: MAX_DOCUMENT_COUNT))
    end

    documents.each do |document|
      unless DOCUMENT_CONTENT_TYPES.include?(document.blob.content_type)
        errors.add(:documents, I18n.t("entries.documents.errors.invalid_type", content_type: document.blob.content_type))
      end

      if document.blob.byte_size > MAX_DOCUMENT_SIZE
        errors.add(:documents, I18n.t("entries.documents.errors.too_large", size: ActiveSupport::NumberHelper.number_to_human_size(MAX_DOCUMENT_SIZE)))
      end
    end
  end

  def facts_must_be_array
    return unless has_attribute?(:facts)
    return if facts.is_a?(Array) && facts.all? { |item| item.is_a?(String) }

    errors.add(:facts, :invalid)
  end

  def llm_response_must_be_hash
    return unless has_attribute?(:llm_response)
    return if self[:llm_response].is_a?(Hash)

    errors.add(:llm_response, :invalid)
  end

  def numeric_value(value)
    return value if value.is_a?(Numeric)
    return value.to_i if value.to_s.match?(/\A-?\d+\z/)
    return value.to_f if value.to_s.match?(/\A-?\d+\.\d+\z/)

    nil
  end

  def parseable_data_value
    has_attribute?(:parseable_data) ? self[:parseable_data] : nil
  end
end
