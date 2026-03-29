require "json"
require "net/http"
require "uri"

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

  def self.call(note:, preference: UserPreference.current)
    return Result.new(data: [], error: :blank_note) if note.blank?

    configuration_error = configuration_error_for(preference)
    return Result.new(data: [], error: configuration_error) if configuration_error.present?

    response_body = request_completion(note, preference)
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

  def self.request_completion(note, preference)
    uri = URI.parse("#{preference.llm_api_base.chomp('/')}/chat/completions")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{preference.llm_runtime_api_key}" if preference.llm_runtime_api_key.present?

    request.body = {
      model: preference.llm_model,
      temperature: 0,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(note) }
      ]
    }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    raise "LLM request failed with status #{response.code}" unless response.code.to_i.between?(200, 299)

    JSON.parse(response.body).dig("choices", 0, "message", "content").to_s
  end

  def self.system_prompt
    <<~PROMPT
      Parse health notes into structured data.

      Return ONLY a JSON array.
      No markdown. No prose. No code fences.

      Rules:
      - Each item must be a JSON object.
      - Each object must include "type".
      - Add "value" when there is a clear primary value or named item.
      - Add "unit" when a unit is explicit or obvious.
      - Add only clearly supported keys such as "side", "dose", "wet", "solid", "rash", "ref", "flag", "location", or "quality".
      - Use lowercase snake_case for common types such as temperature, pulse, weight, bottle_feeding, breast_feeding, diaper, medication, sleep, and symptom.
      - Preserve uppercase lab names such as WBC or CRP.
      - Use JSON numbers for numeric values, not strings.
      - Do not invent diagnoses or facts.
      - If nothing structured can be extracted, return [].

      Examples:
      Peter has high temp 35 degree
      [{"type":"temperature","value":35,"unit":"C","flag":"low"}]

      Peter has fever 39.2
      [{"type":"temperature","value":39.2,"unit":"C","flag":"high"}]

      Peter pulse 128
      [{"type":"pulse","value":128,"unit":"bpm"}]

      Peter weighs 12.4 kg
      [{"type":"weight","value":12.4,"unit":"kg"}]

      Peter breastfed left side for 18 minutes
      [{"type":"breast_feeding","value":18,"unit":"min","side":"left"}]

      Peter drank 120 ml bottle
      [{"type":"bottle_feeding","value":120,"unit":"ml"}]

      Peter diaper wet
      [{"type":"diaper","wet":true,"solid":false}]

      Peter diaper solid
      [{"type":"diaper","wet":false,"solid":true}]

      Peter diaper wet and solid
      [{"type":"diaper","wet":true,"solid":true}]

      Peter diaper wet and rash
      [{"type":"diaper","wet":true,"solid":false,"rash":true}]

      Peter got ibuprofen 400mg
      [{"type":"medication","value":"ibuprofen","dose":"400mg"}]

      Peter slept 95 min
      [{"type":"sleep","value":95,"unit":"min"}]

      Elderly patient WBC 11.2 G/L and CRP 3.1
      [{"type":"WBC","value":11.2,"unit":"G/L","ref":"4.0-10.0","flag":"high"},{"type":"CRP","value":3.1}]

      Elderly patient took ibuprofen 400mg for knee pain
      [{"type":"medication","value":"ibuprofen","dose":"400mg"},{"type":"symptom","value":"knee pain"}]

      Elderly patient coughing and mild fever 38.1
      [{"type":"symptom","value":"cough"},{"type":"temperature","value":38.1,"unit":"C","flag":"high"}]

      Peter seems fine today
      []
    PROMPT
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
