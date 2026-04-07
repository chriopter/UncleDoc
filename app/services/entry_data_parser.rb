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
    "lab" => "lab_result",
    "lab_result" => "lab_result",
    "blood_test" => "lab_result",
    "bloodwork" => "lab_result",
    "blood_pressure" => "blood_pressure",
    "blood pressure" => "blood_pressure",
    "bp" => "blood_pressure",
    "healthkit" => "healthkit_summary",
    "health_summary" => "healthkit_summary",
    "apple_health" => "healthkit_summary",
    "apple_health_summary" => "healthkit_summary",
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

  HEALTHKIT_METRIC_PATTERNS = [
    [ /\AStep count (?<value>-?\d+(?:\.\d+)?) (?<unit>count)\.?\z/i, "Step count" ],
    [ /\AWalking and running distance (?<value>-?\d+(?:\.\d+)?) (?<unit>km|m)\.?\z/i, "Walking and running distance" ],
    [ /\ACycling distance (?<value>-?\d+(?:\.\d+)?) (?<unit>km|m)\.?\z/i, "Cycling distance" ],
    [ /\AActive energy burned (?<value>-?\d+(?:\.\d+)?) (?<unit>kcal)\.?\z/i, "Active energy burned" ],
    [ /\ABasal energy burned (?<value>-?\d+(?:\.\d+)?) (?<unit>kcal)\.?\z/i, "Basal energy burned" ],
    [ /\AFlights climbed (?<value>-?\d+(?:\.\d+)?) (?<unit>count)\.?\z/i, "Flights climbed" ],
    [ /\AWalking speed avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "Walking speed" ],
    [ /\AWalking step length avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "Walking step length" ],
    [ /\AHeart rate variability avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "Heart rate variability" ],
    [ /\ARespiratory rate avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "Respiratory rate" ],
    [ /\AOxygen saturation avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "Oxygen saturation" ],
    [ /\AVO2 max avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "VO2 max" ],
    [ /\ADietary energy consumed (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "Dietary energy consumed" ],
    [ /\ADietary carbohydrates (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "Dietary carbohydrates" ],
    [ /\ADietary protein (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "Dietary protein" ],
    [ /\ADietary fat (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "Dietary fat" ],
    [ /\ADietary sugar (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "Dietary sugar" ],
    [ /\ADietary water (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "Dietary water" ]
  ].freeze

  def self.call(input:, preference: UserPreference.current, entry: nil)
    return Result.new(facts: [], parseable_data: [], occurred_at: nil, llm_response: {}, error: :blank_input) if input.blank? && entry_documents(entry).blank?

    configuration_error = configuration_error_for(preference)
    return Result.new(facts: [], parseable_data: [], occurred_at: nil, llm_response: {}, error: configuration_error) if configuration_error.present?

    payload = request_payload_with_retry(input, preference, entry: entry)
    parseable_data = sanitize_parseable_data(payload["parseable_data"])
    parseable_data = enrich_healthkit_parseable_data(parseable_data, input, entry: entry)

    Result.new(
      facts: sanitize_facts(payload["facts"]),
      parseable_data: parseable_data,
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
    if entry_documents(entry).present?
      begin
        return request_multimodal_completion(input, preference, entry: entry)
      rescue StandardError
        fallback_input = fallback_document_input(input, entry)
        return request_text_completion(fallback_input, preference, entry: entry) if fallback_input.present?

        raise
      end
    end

    request_text_completion(input, preference, entry: entry)
  end

  def self.request_text_completion(input, preference, entry: nil)
    LlmChatRequest.call(
      request_kind: "entry_parse",
      preference: preference,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(input, entry: entry) }
      ],
      person: entry&.person,
      entry: entry,
      temperature: 0
    ).content
  end

  def self.request_multimodal_completion(input, preference, entry: nil)
    last_response = nil
    last_error = nil

    multimodal_models_for(preference).each do |model|
      content = LlmMultimodalRequest.call(
        request_kind: "entry_parse",
        preference: preference,
        instructions: system_prompt,
        prompt: user_prompt(input, entry: entry),
        attachments: entry_documents(entry),
        person: entry&.person,
        entry: entry,
        temperature: 0,
        model:
      ).content

      last_response = content
      payload = parse_json_object(content)
      return content if document_payload_useful?(payload)
    rescue StandardError => error
      last_error = error
    end

    raise last_error if last_response.blank? && last_error

    last_response.to_s
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
    File.read(Rails.root.join("prompts/parser.md"))
  end

  def self.user_prompt(input, entry: nil)
    <<~PROMPT.strip
      Current time: #{Time.current.iso8601}
      Time zone: #{Time.zone.tzinfo.name}
      Entry source: #{entry&.respond_to?(:source) ? entry.source.presence || "manual" : "manual"}
      Entry reference: #{entry&.respond_to?(:source_ref) ? entry.source_ref.presence || "none" : "none"}
      Input: #{input.presence || "(none)"}
      Attached documents: #{document_list(entry)}
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

      sanitized = item.deep_stringify_keys.slice("type", "value", "result", "unit", "side", "dose", "wet", "solid", "rash", "ref", "flag", "location", "quality", "systolic", "diastolic", "scheduled_for", "due_at")
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

  def self.entry_documents(entry)
    return [] unless entry&.respond_to?(:documents)
    return [] unless entry.documents.attached?

    entry.documents.blobs
  end

  def self.document_list(entry)
    names = entry_documents(entry).map { |document| document.filename.to_s }
    names.any? ? names.join(", ") : "none"
  end

  def self.multimodal_models_for(preference)
    models = [ preference.llm_model ]

    if preference.llm_provider == "openrouter" && preference.llm_model == "openai/gpt-5.4"
      models.unshift("openai/gpt-4.1-mini")
    end

    models.compact.uniq
  end

  def self.document_payload_useful?(payload)
    facts = sanitize_facts(payload["facts"])
    data = sanitize_parseable_data(payload["parseable_data"])
    facts.present? || data.present?
  end

  def self.enrich_healthkit_parseable_data(parseable_data, input, entry: nil)
    return parseable_data unless entry&.respond_to?(:source) && entry.source == Entry::SOURCES[:healthkit]

    enriched = parseable_data.deep_dup
    summary_quality = entry.source_ref.to_s.start_with?("healthkit:month:") || input.to_s.downcase.include?("monthly summary") ? "monthly" : "daily"

    unless enriched.any? { |item| item["type"] == "healthkit_summary" }
      enriched << { "type" => "healthkit_summary", "value" => "Apple Health", "quality" => summary_quality }
    end

    lines = input.to_s.split("\n").map { |line| line.strip.sub(/\A-\s*/, "").sub(/\.$/, "") }.reject(&:blank?)

    blood_pressure = {}

    lines.each do |line|
      case line
      when /\AWeight (?<value>-?\d+(?:\.\d+)?) (?<unit>kg|lb)\z/i
        append_unique_measurement(enriched, "weight", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\AHeight (?<value>-?\d+(?:\.\d+)?) (?<unit>cm|m)\z/i
        append_unique_measurement(enriched, "height", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\ABody temperature(?: avg)? (?<value>-?\d+(?:\.\d+)?) (?<unit>C|F)\z/i
        append_unique_measurement(enriched, "temperature", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\A(?:Resting pulse|Walking pulse|Pulse) avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\z/i
        append_unique_measurement(enriched, "pulse", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\ASleep (?<value>-?\d+(?:\.\d+)?) hours(?: across .*?)?\z/i
        append_unique_measurement(enriched, "sleep", Regexp.last_match[:value], "h")
      when /\ABlood pressure systolic avg (?<value>-?\d+(?:\.\d+)?) (?<unit>mmHg)\z/i
        blood_pressure["systolic"] = normalize_value(Regexp.last_match[:value])
        blood_pressure["unit"] = Regexp.last_match[:unit]
      when /\ABlood pressure diastolic avg (?<value>-?\d+(?:\.\d+)?) (?<unit>mmHg)\z/i
        blood_pressure["diastolic"] = normalize_value(Regexp.last_match[:value])
        blood_pressure["unit"] = Regexp.last_match[:unit]
      else
        metric_name, metric_value, metric_unit = healthkit_metric_from_line(line)
        next unless metric_name

        append_unique_lab_result(enriched, metric_name, metric_value, metric_unit)
      end
    end

    if blood_pressure["systolic"].present? && blood_pressure["diastolic"].present? && enriched.none? { |item| item["type"] == "blood_pressure" }
      enriched << {
        "type" => "blood_pressure",
        "systolic" => blood_pressure["systolic"],
        "diastolic" => blood_pressure["diastolic"],
        "unit" => blood_pressure["unit"] || "mmHg"
      }
    end

    sanitize_parseable_data(enriched)
  end

  def self.healthkit_metric_from_line(line)
    HEALTHKIT_METRIC_PATTERNS.each do |pattern, label|
      match = line.match(pattern)
      next unless match

      return [ label, match[:value], match[:unit] ]
    end

    if (match = line.match(/\AWorkouts (?<count>-?\d+(?:\.\d+)?) with (?<minutes>-?\d+(?:\.\d+)?) total minutes\z/i))
      return [ "Workouts", match[:count], "count" ]
    end

    if (match = line.match(/\AAudio exposure events (?<count>-?\d+(?:\.\d+)?) with (?<minutes>-?\d+(?:\.\d+)?) total minutes\z/i))
      return [ "Audio exposure events", match[:count], "count" ]
    end

    nil
  end

  def self.append_unique_measurement(items, type, value, unit)
    return if items.any? { |item| item["type"] == type }

    items << { "type" => type, "value" => value, "unit" => unit }
  end

  def self.append_unique_lab_result(items, name, value, unit)
    return if items.any? { |item| item["type"] == "lab_result" && item["value"] == name }

    items << { "type" => "lab_result", "value" => name, "result" => value, "unit" => unit }
  end

  def self.fallback_document_input(input, entry)
    extracted = DocumentTextExtractor.extract_many(entry_documents(entry))
    return input if extracted.blank?
    return extracted if input.blank?

    [ input, extracted ].join("\n\n")
  end
end
