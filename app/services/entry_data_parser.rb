require "json"
class EntryDataParser
  Result = Struct.new(:data, :error, keyword_init: true)

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

  def self.call(note:, preference: UserPreference.current, entry: nil)
    return Result.new(data: [], error: :blank_note) if note.blank?

    configuration_error = configuration_error_for(preference)
    return Result.new(data: [], error: configuration_error) if configuration_error.present?

    response_body = request_completion(note, preference, entry: entry)
    Result.new(data: sanitize_data(parse_json_array(response_body)))
  rescue StandardError => error
    Rails.logger.warn("Entry data parse failed: #{error.class}: #{error.message}")
    Result.new(data: [], error: :request_failed)
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

  def self.request_completion(note, preference, entry: nil)
    LlmChatRequest.call(
      request_kind: "entry_parse",
      preference: preference,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(note) }
      ],
      person: entry&.person,
      entry: entry,
      temperature: 0
    ).content
  end

  def self.system_prompt
    @system_prompt ||= File.read(Rails.root.join("config/parsers/entry_data.txt"))
  end

  def self.user_prompt(note)
    "Note: #{note}"
  end

  def self.parse_json_array(response_body)
    cleaned = response_body.to_s.strip
    cleaned = cleaned.gsub(/\A```(?:json)?\s*/m, "").gsub(/\s*```\z/m, "")

    start_index = cleaned.index("[")
    end_index = cleaned.rindex("]")
    raise JSON::ParserError, "No JSON array found" unless start_index && end_index

    JSON.parse(cleaned[start_index..end_index])
  end

  def self.sanitize_data(value)
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
      sanitized.compact_blank
    end
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
