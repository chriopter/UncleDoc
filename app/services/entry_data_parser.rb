require "json"
class EntryDataParser
  Result = Struct.new(:facts, :parseable_data, :occurred_at, :llm_response, :error, keyword_init: true)
  MAX_ATTEMPTS = 2

  TEMPERATURE_FLAG_ALIASES = {
    "fever" => "high",
    "fieber" => "high"
  }.freeze

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
    "heart_rate" => "pulse",
    "body_length" => "height",
    "length" => "height",
    "size" => "height",
    "vaccine" => "vaccination",
    "vaccination" => "vaccination",
    "impfung" => "vaccination",
    "blood_pressure" => "blood_pressure",
    "blood pressure" => "blood_pressure",
    "bp" => "blood_pressure",
    "task" => "todo",
    "to_do" => "todo",
    "appointment" => "appointment",
    "termin" => "appointment",
    "note" => "todo",
    "memo" => "todo"
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
    return Result.new(facts: [], parseable_data: [], occurred_at: nil, llm_response: {}, error: :blank_input) if input.blank?

    configuration_error = configuration_error_for(preference)
    return Result.new(facts: [], parseable_data: [], occurred_at: nil, llm_response: {}, error: configuration_error) if configuration_error.present?

    payload = request_payload_with_retry(input, preference, entry: entry)
    Result.new(
      facts: sanitize_facts(payload["facts"]),
      parseable_data: sanitize_parseable_data(payload["parseable_data"]),
      occurred_at: sanitize_occurred_at(payload["occurred_at"]),
      llm_response: sanitize_llm_response(payload["llm_response"])
    )
  rescue StandardError => error
    Rails.logger.warn("Entry parsing failed: #{error.class}: #{error.message}")
    fallback = fallback_result_for(input)
    return fallback if fallback

    Result.new(facts: [], parseable_data: [], occurred_at: nil, llm_response: {}, error: :request_failed)
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

  def self.request_payload_with_retry(input, preference, entry: nil)
    attempts = 0

    begin
      attempts += 1
      response_body = request_completion(input, preference, entry: entry)
      raise JSON::ParserError, "Empty response body" if response_body.to_s.strip.blank?

      parse_json_object(response_body)
    rescue JSON::ParserError => error
      raise error if attempts >= MAX_ATTEMPTS

      Rails.logger.warn("Entry parsing retry after invalid response: #{error.message}")
      retry
    end
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

      sanitized = item.deep_stringify_keys.slice("type", "value", "unit", "side", "dose", "wet", "solid", "rash", "ref", "flag", "location", "quality", "systolic", "diastolic", "scheduled_for", "due_at")
      type = normalize_type(sanitized["type"])
      next if type.blank?

      sanitized["type"] = type
      sanitized["unit"] = normalize_unit(sanitized["unit"]) if sanitized["unit"].present?
      sanitized["flag"] = normalize_flag(type, sanitized["flag"]) if sanitized["flag"].present?
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

  def self.sanitize_llm_response(value)
    return {} unless value.is_a?(Hash)

    value.deep_stringify_keys.slice("status", "confidence", "note").transform_values do |entry|
      entry.to_s.strip.presence
    end.compact
  end

  def self.fallback_result_for(input)
    return if input.blank?

    normalized_input = input.to_s.strip
    return if normalized_input.blank?

    if todo_like?(normalized_input)
      Result.new(
        facts: [ normalized_input ],
        parseable_data: [ { "type" => "todo", "value" => normalized_input } ],
        occurred_at: nil,
        llm_response: {
          "status" => "structured",
          "confidence" => "low",
          "note" => "Fallback parser mapped an actionable reminder to canonical todo after the LLM returned no usable response."
        }
      )
    end
  end

  def self.todo_like?(input)
    input.match?(/\A\s*(check|bring|call|ask|remember|book|schedule|buy|organize|todo|to do|pru?fe|checke|mitbringen|anrufen|fragen|merken|besorgen)\b/i)
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

  def self.normalize_flag(type, flag)
    normalized = flag.to_s.strip.downcase
    return if normalized.blank?

    return TEMPERATURE_FLAG_ALIASES.fetch(normalized, normalized) if type == "temperature"

    normalized
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
