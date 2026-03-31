require "json"
class EntryDataParser
  Result = Struct.new(:facts, :parseable_data, :occurred_at, :error, keyword_init: true)

  TYPE_ALIASES = {
    "temp" => "temperature",
    "temperature_c" => "temperature",
    "fever" => "temperature",
    "bottle" => "bottle_feeding",
    "bottlefeeding" => "bottle_feeding",
    "bottle_feeding" => "bottle_feeding",
    "breastfeeding" => "breast_feeding",
    "breast_fed" => "breast_feeding",
    "breast_feed" => "breast_feeding",
    "nursing" => "breast_feeding",
    "heart_rate" => "pulse"
  }.freeze

  UNIT_ALIASES = {
    "°c" => "C",
    "celsius" => "C",
    "mls" => "ml",
    "milliliters" => "ml",
    "mins" => "min",
    "minutes" => "min",
    "minute" => "min",
    "beats/min" => "bpm"
  }.freeze

  def self.call(input:, preference: UserPreference.current, entry: nil)
    return Result.new(facts: [], parseable_data: [], occurred_at: nil, error: :blank_input) if input.blank?

    configuration_error = configuration_error_for(preference)
    return Result.new(facts: [], parseable_data: [], occurred_at: nil, error: configuration_error) if configuration_error.present?

    response_body = request_completion(input, preference, entry: entry)
    payload = parse_json_object(response_body)
    Result.new(
      facts: sanitize_facts(payload["facts"]),
      parseable_data: sanitize_parseable_data(payload["parseable_data"]),
      occurred_at: sanitize_occurred_at(payload["occurred_at"])
    )
  rescue StandardError => error
    Rails.logger.warn("Entry parsing failed: #{error.class}: #{error.message}")
    Result.new(facts: [], parseable_data: [], occurred_at: nil, error: :request_failed)
  end

  def self.ready?(preference = UserPreference.current)
    configuration_error_for(preference).nil?
  end

  def self.configuration_error_for(preference)
    return :missing_model if preference.llm_model.blank?
    return :missing_api_key if preference.llm_runtime_api_key.blank? && preference.llm_ruby_provider != :ollama
    return :unsupported_provider unless preference.llm_openai_compatible?

    nil
  end

  def self.request_completion(input, preference, entry: nil)
    LlmChatRequest.call(
      request_kind: "entry_parse",
      preference: preference,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(input) }
      ],
      person: entry&.person,
      entry: entry,
      temperature: 0
    ).content
  end

  def self.system_prompt
    File.read(Rails.root.join("config/parsers/entry_data.txt"))
  end

  def self.user_prompt(input)
    <<~PROMPT.strip
      Current time: #{Time.current.iso8601}
      Time zone: #{Time.zone.tzinfo.name}
      Input: #{input}
    PROMPT
  end

  def self.parse_json_object(response_body)
    cleaned = response_body.to_s.strip
    cleaned = cleaned.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "")

    start_index = cleaned.index("{")
    end_index = cleaned.rindex("}")
    raise JSON::ParserError, "No JSON object found" unless start_index && end_index

    payload = JSON.parse(cleaned[start_index..end_index])
    raise JSON::ParserError, "Expected JSON object" unless payload.is_a?(Hash)

    payload
  end

  def self.sanitize_facts(value)
    return [] unless value.is_a?(Array)

    value.filter_map do |item|
      item.to_s.strip.presence
    end
  end

  def self.sanitize_parseable_data(value)
    return [] unless value.is_a?(Array)

    value.filter_map do |item|
      next unless item.is_a?(Hash)

      sanitized = item.deep_stringify_keys.slice("type", "value", "unit", "side", "dose", "wet", "solid", "rash", "ref", "flag", "location", "quality")
      type = normalize_type(sanitized["type"])
      next if type.blank?

      sanitized["type"] = type
      sanitized["unit"] = normalize_unit(sanitized["unit"]) if sanitized["unit"].present?
      sanitized["flag"] = sanitized["flag"].to_s.downcase if sanitized["flag"].present?
      sanitized.transform_values! { |entry| normalize_value(entry) }
      sanitized.reject { |_key, entry| entry.blank? && entry != false }
    end
  end

  def self.sanitize_occurred_at(value)
    return if value.blank?
    return if value.to_s.strip.casecmp("null").zero?

    parsed = case value
    when Time, DateTime, ActiveSupport::TimeWithZone
      value.in_time_zone
    else
      Time.zone.parse(value.to_s)
    end

    parsed&.iso8601.present? ? parsed : nil
  rescue ArgumentError, TypeError
    nil
  end

  def self.normalize_type(type)
    raw = type.to_s.strip
    return if raw.blank?
    return raw.upcase if raw.match?(/\A[A-Z]{2,}[A-Za-z0-9]*\z/)

    normalized = raw.downcase.strip.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
    TYPE_ALIASES.fetch(normalized, normalized)
  end

  def self.normalize_unit(unit)
    normalized = unit.to_s.strip
    return if normalized.blank?

    UNIT_ALIASES.fetch(normalized.downcase, normalized)
  end

  def self.normalize_value(value)
    case value
    when String
      stripped = value.strip
      return true if stripped.casecmp("true").zero?
      return false if stripped.casecmp("false").zero?
      return stripped.to_i if stripped.match?(/\A-?\d+\z/)
      return stripped.to_f if stripped.match?(/\A-?\d+\.\d+\z/)

      stripped
    else
      value
    end
  end
end
