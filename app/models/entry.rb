class Entry < ApplicationRecord
  belongs_to :person
  has_many_attached :documents

  PARSE_STATUSES = %w[pending parsed failed skipped].freeze
  SOURCES = { manual: "manual", babywidget: "babywidget", healthkit: "healthkit" }.freeze
  FACT_KINDS = %w[measurement appointment todo medication vaccination symptom summary note].freeze
  DOCUMENT_CONTENT_TYPES = %w[application/pdf image/png image/jpeg text/plain].freeze
  MAX_DOCUMENT_COUNT = 5
  MAX_DOCUMENT_SIZE = 10.megabytes

  validates :occurred_at, presence: true
  validates :parse_status, inclusion: { in: PARSE_STATUSES }
  validates :source, inclusion: { in: SOURCES.values }
  validate :extracted_data_must_be_hash
  validate :fact_objects_must_be_valid
  validate :llm_metadata_must_be_hash
  validate :input_or_documents_present
  validate :documents_are_supported

  after_initialize :normalize_defaults

  scope :recent_first, -> { order(occurred_at: :desc, created_at: :desc) }
  scope :entered_first, -> { order(created_at: :desc, occurred_at: :desc) }
  scope :with_documents, -> { includes(documents_attachments: :blob).where.associated(:documents_attachments).distinct }
  scope :healthkit_generated, -> { where(source: SOURCES[:healthkit]) }
  scope :babywidget_generated, -> { where(source: SOURCES[:babywidget]) }
  scope :by_parseable_data_type, ->(type) {
    normalized_type = type.to_s
    facts_path = "json_each(entries.extracted_data, '$.facts')"

    case normalized_type
    when "appointment", "todo", "medication", "vaccination", "symptom", "note"
      where("EXISTS (SELECT 1 FROM #{facts_path} WHERE json_extract(value, '$.kind') = ?)", normalized_type)
    when "healthkit_summary"
      where("EXISTS (SELECT 1 FROM #{facts_path} WHERE json_extract(value, '$.kind') = 'summary' AND json_extract(value, '$.value') = 'Apple Health')")
    else
      where("EXISTS (SELECT 1 FROM #{facts_path} WHERE json_extract(value, '$.kind') = 'measurement' AND json_extract(value, '$.metric') = ?)", normalized_type)
    end
  }

  def fact_objects
    facts_value.is_a?(Array) ? facts_value.filter_map { |item| item.is_a?(Hash) ? item.deep_stringify_keys : nil } : []
  end

  def facts
    fact_items
  end

  def facts=(value)
    @legacy_fact_texts = Array(value).filter_map do |item|
      case item
      when Hash
        normalized = item.deep_stringify_keys
        normalized["text"].to_s.strip.presence
      else
        item.to_s.strip.presence
      end
    end
    sync_legacy_payloads
  end

  def llm_response
    llm_metadata
  end

  def llm_response=(value)
    update_extracted_data("llm", normalize_hash(value))
  end

  def parseable_data
    fact_objects.filter_map { |fact| legacy_parseable_item_for(fact) }
  end

  def parseable_data=(value)
    @legacy_parseable_data = Array(value).filter_map { |item| item.is_a?(Hash) ? item.deep_stringify_keys : nil }
    sync_legacy_payloads
  end

  def parseable_data_of_type(type)
    parseable_data.select { |item| item["type"] == type }
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
    fact_objects.any? { |fact| fact["kind"] == "appointment" }
  end

  def todo?
    fact_objects.any? { |fact| fact["kind"] == "todo" }
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
    fact_objects.find { |fact| fact["kind"] == "appointment" } || {}
  end

  def todo_data
    fact_objects.find { |fact| fact["kind"] == "todo" } || {}
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
    fact_objects.filter_map { |fact| fact["text"].to_s.strip.presence }
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
    parse_status == "pending"
  end

  def parsed?
    parse_status == "parsed"
  end

  def failed_parse?
    parse_status == "failed"
  end

  def skipped_parse?
    parse_status == "skipped"
  end

  def todo_open?
    todo? && !todo_done?
  end

  def healthkit_generated?
    source == SOURCES[:healthkit]
  end

  def babywidget_generated?
    source == SOURCES[:babywidget]
  end

  def todo_title
    todo_data["value"].presence
  end

  def appointment_title
    appointment_data["value"].presence
  end

  def llm_metadata
    llm_value.is_a?(Hash) ? llm_value.deep_stringify_keys : {}
  end

  def time_since
    return nil unless display_time

    Time.current - display_time
  end

  def self.sorted_by(mode)
    mode.to_s == "entered" ? entered_first : recent_first
  end

  private

  def normalize_defaults
    self.extracted_data = default_extracted_data if extracted_data.blank?
    self.occurred_at ||= Time.current
    self.parse_status ||= fact_objects.present? ? "parsed" : "pending"
  end

  def sync_legacy_payloads
    fact_texts = @legacy_fact_texts.nil? ? fact_items : @legacy_fact_texts
    parseable_items = @legacy_parseable_data.nil? ? parseable_data : @legacy_parseable_data
    fact_objects = self.class.build_fact_objects_from_legacy(fact_texts, parseable_items)
    update_extracted_data("facts", fact_objects)
  end

  def extracted_data_must_be_hash
    errors.add(:extracted_data, :invalid) unless extracted_data.is_a?(Hash)
  end

  def fact_objects_must_be_valid
    fact_objects.each do |fact|
      errors.add(:extracted_data, :invalid) and return if fact["text"].to_s.strip.blank?
      errors.add(:extracted_data, :invalid) and return unless FACT_KINDS.include?(fact["kind"])
    end
  end

  def llm_metadata_must_be_hash
    errors.add(:extracted_data, :invalid) unless llm_metadata.is_a?(Hash)
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

  def numeric_value(value)
    return value if value.is_a?(Numeric)
    return value.to_i if value.to_s.match?(/\A-?\d+\z/)
    return value.to_f if value.to_s.match?(/\A-?\d+\.\d+\z/)

    nil
  end

  def facts_value
    extracted_data.is_a?(Hash) ? extracted_data["facts"] || extracted_data[:facts] : []
  end

  def llm_value
    extracted_data.is_a?(Hash) ? extracted_data["llm"] || extracted_data[:llm] : {}
  end

  def update_extracted_data(key, value)
    base = extracted_data.is_a?(Hash) ? extracted_data.deep_stringify_keys : default_extracted_data
    base[key] = value
    self.extracted_data = base
  end

  def default_extracted_data
    { "facts" => [], "llm" => {} }
  end

  def normalize_hash(value)
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def legacy_parseable_item_for(fact)
    case fact["kind"]
    when "measurement"
      measurement_parseable_item_for(fact)
    when "medication", "vaccination", "appointment", "todo", "symptom", "note"
      fact.slice("value", "dose", "location", "quality", "scheduled_for", "due_at", "flag", "ref", "result").merge("type" => fact["kind"])
    when "summary"
      return nil unless fact["value"] == "Apple Health"

      { "type" => "healthkit_summary", "value" => fact["value"], "quality" => fact["quality"] }.compact
    end
  end

  def measurement_parseable_item_for(fact)
    metric = fact["metric"].presence
    return unless metric

    item = { "type" => metric }
    %w[value unit side dose wet solid rash flag location quality systolic diastolic scheduled_for due_at ref result].each do |key|
      item[key] = fact[key] if fact.key?(key)
    end
    item.compact
  end

  class << self
    def build_fact_objects_from_legacy(fact_texts, parseable_items)
      texts = Array(fact_texts)
      items = Array(parseable_items).filter_map { |item| item.is_a?(Hash) ? item.deep_stringify_keys : nil }

      if items.present?
        built_facts = items.each_with_index.map do |item, index|
          build_fact_object_from_legacy_item(item, texts[index])
        end.compact

        extra_texts = texts.drop(items.length)
        built_facts + extra_texts.filter_map { |text| note_fact(text) }
      else
        texts.filter_map { |text| note_fact(text) }
      end
    end

    def build_fact_object_from_legacy_item(item, text = nil)
      type = item["type"].to_s
      text = "Apple Health #{item['quality'].presence || 'daily'} summary" if type == "healthkit_summary"
      text ||= EntryFactListBuilder.call([ item ]).first
      return unless text.present?

      case type
      when "appointment", "todo", "medication", "vaccination", "symptom", "note"
        fact_hash(text, type, item.except("type"))
      when "healthkit_summary"
        fact_hash(text, "summary", item.except("type"))
      else
        fact_hash(text, "measurement", item.except("type").merge("metric" => type))
      end
    end

    def note_fact(text)
      normalized_text = text.to_s.strip
      return if normalized_text.blank?

      fact_hash(normalized_text, "note", {})
    end

    def fact_hash(text, kind, attributes)
      normalized = { "text" => text.to_s.strip, "kind" => kind.to_s }
      attributes.each do |key, value|
        value = normalize_legacy_attribute_value(value)
        next if value.blank? && value != false

        normalized[key.to_s] = value
      end
      normalized
    end

    def normalize_legacy_attribute_value(value)
      return true if value == "true"
      return false if value == "false"
      return value.to_i if value.is_a?(String) && value.match?(/\A-?\d+\z/)
      return value.to_f if value.is_a?(String) && value.match?(/\A-?\d+\.\d+\z/)

      value
    end
  end
end
