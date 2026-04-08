require "json"

class EntryDataParser
  class Result
    attr_reader :fact_objects, :occurred_at, :document, :llm, :error

    def initialize(facts: nil, fact_objects: nil, occurred_at: nil, document: nil, llm: nil, llm_response: nil, parseable_data: nil, error: nil, **)
      @fact_objects = Array(fact_objects || facts)
      if parseable_data.present? && (@fact_objects.blank? || @fact_objects.all? { |item| item.is_a?(String) })
        @fact_objects = Entry.build_fact_objects_from_legacy(@fact_objects, parseable_data)
      elsif @fact_objects.all? { |item| item.is_a?(String) }
        @fact_objects = Entry.build_fact_objects_from_legacy(@fact_objects, [])
      end
      @occurred_at = occurred_at
      @document = (document || {}).deep_stringify_keys
      @llm = (llm || llm_response || {}).deep_stringify_keys
      @error = error
    end

    def facts
      fact_texts
    end

    def fact_texts
      fact_objects.filter_map { |fact| fact["text"].presence }
    end

    def parseable_data
      fact_objects.filter_map { |fact| Entry.new.send(:legacy_parseable_item_for, fact) }
    end

    def llm_response
      llm
    end
  end
  MAX_ATTEMPTS = 2

  HEALTHKIT_FACT_PATTERNS = [
    [ /\AStep count (?<value>-?\d+(?:\.\d+)?) (?<unit>count)\.?\z/i, "step_count", "Step count" ],
    [ /\AWalking and running distance (?<value>-?\d+(?:\.\d+)?) (?<unit>km|m)\.?\z/i, "walking_distance", "Walking and running distance" ],
    [ /\ACycling distance (?<value>-?\d+(?:\.\d+)?) (?<unit>km|m)\.?\z/i, "cycling_distance", "Cycling distance" ],
    [ /\AActive energy burned (?<value>-?\d+(?:\.\d+)?) (?<unit>kcal)\.?\z/i, "active_energy", "Active energy burned" ],
    [ /\ABasal energy burned (?<value>-?\d+(?:\.\d+)?) (?<unit>kcal)\.?\z/i, "basal_energy", "Basal energy burned" ],
    [ /\AFlights climbed (?<value>-?\d+(?:\.\d+)?) (?<unit>count)\.?\z/i, "flights_climbed", "Flights climbed" ],
    [ /\AWalking speed avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "walking_speed", "Walking speed avg" ],
    [ /\AWalking step length avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "walking_step_length", "Walking step length avg" ],
    [ /\AHeart rate variability avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "heart_rate_variability", "Heart rate variability avg" ],
    [ /\ARespiratory rate avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "respiratory_rate", "Respiratory rate avg" ],
    [ /\AOxygen saturation avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "oxygen_saturation", "Oxygen saturation avg" ],
    [ /\AVO2 max avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\.?\z/i, "vo2_max", "VO2 max avg" ],
    [ /\ADietary energy consumed (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "dietary_energy", "Dietary energy consumed" ],
    [ /\ADietary carbohydrates (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "dietary_carbohydrates", "Dietary carbohydrates" ],
    [ /\ADietary protein (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "dietary_protein", "Dietary protein" ],
    [ /\ADietary fat (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "dietary_fat", "Dietary fat" ],
    [ /\ADietary sugar (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "dietary_sugar", "Dietary sugar" ],
    [ /\ADietary water (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)\.?\z/i, "dietary_water", "Dietary water" ]
  ].freeze

  def self.call(input:, preference: AppSetting.current, entry: nil)
    return Result.new(facts: [], occurred_at: nil, document: {}, llm: {}, error: :blank_input) if input.blank? && entry_documents(entry).blank?

    configuration_error = configuration_error_for(preference)
    return Result.new(facts: [], occurred_at: nil, document: {}, llm: {}, error: configuration_error) if configuration_error.present?

    payload = request_payload_with_retry(input, preference, entry: entry)
    facts = sanitize_facts(payload["facts"])
    facts = merge_legacy_payload(payload, facts)
    facts = enrich_healthkit_facts(facts, input, entry: entry)

    Result.new(
      facts: facts,
      occurred_at: sanitize_occurred_at(payload["occurred_at"]),
      document: entry_documents(entry).present? ? sanitize_document(payload["document"]) : {},
      llm: sanitize_llm(payload["llm"] || payload["llm_response"])
    )
  rescue StandardError => error
    Rails.logger.warn("Entry parsing failed: #{error.class}: #{error.message}")
    Result.new(facts: [], occurred_at: nil, document: {}, llm: {}, error: :request_failed)
  end

  def self.ready?(preference = AppSetting.current)
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
    prompts = [ user_prompt(input, entry: entry), attachment_ocr_retry_prompt(input, entry: entry) ]

    multimodal_models_for(preference).each do |model|
      prompts.each do |prompt|
        content = LlmMultimodalRequest.call(
          request_kind: "entry_parse",
          preference: preference,
          instructions: system_prompt,
          prompt: prompt,
          attachments: entry_documents(entry),
          person: entry&.person,
          entry: entry,
          temperature: 0,
          model: model
        ).content

        last_response = content
        payload = parse_json_object(content)
        return content if document_payload_useful?(payload)
      end
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
      sanitize_fact(item)
    end
  end

  def self.sanitize_fact(item)
    return sanitize_string_fact(item) if item.is_a?(String)
    return unless item.is_a?(Hash)

    source = item.deep_stringify_keys
    text = source["text"].to_s.strip
    kind = source["kind"].to_s.strip.downcase
    return if text.blank? || kind.blank?

    fact = { "text" => text, "kind" => kind }
    %w[metric value unit result ref flag side dose wet solid rash location quality systolic diastolic scheduled_for due_at].each do |key|
      next unless source.key?(key)

      normalized_value = normalize_value(source[key])
      next if normalized_value.blank? && normalized_value != false

      fact[key] = normalized_value
    end

    fact["metric"] = normalize_metric(fact["metric"]) if fact["metric"].present?
    fact["unit"] = normalize_unit(fact["unit"]) if fact["unit"].present?
    normalize_measurement_fact!(fact)
    fact
  end

  def self.sanitize_string_fact(item)
    text = item.to_s.strip
    return if text.blank?

    { "text" => text, "kind" => "note" }
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

  def self.sanitize_llm(value)
    return {} unless value.is_a?(Hash)

    value.deep_stringify_keys.slice("status", "confidence", "note").transform_values do |entry|
      entry.to_s.strip.presence
    end.compact
  end

  def self.sanitize_document(value)
    return {} unless value.is_a?(Hash)

    value.deep_stringify_keys.slice("type", "title").transform_values do |item|
      item.to_s.strip.presence
    end.compact
  end

  def self.normalize_metric(metric)
    metric.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
  end

  def self.normalize_unit(unit)
    normalized = unit.to_s.strip
    return if normalized.blank?

    {
      "°c" => "C",
      "celsius" => "C",
      "mls" => "ml",
      "milliliters" => "ml",
      "mins" => "min",
      "minutes" => "min",
      "minute" => "min",
      "beats/min" => "bpm",
      "count/min" => "bpm"
    }.fetch(normalized.downcase, normalized)
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

  def self.normalize_measurement_fact!(fact)
    return fact unless fact["kind"] == "measurement"
    return fact unless fact["metric"] == "pulse"

    case fact["unit"]
    when "count/s"
      fact["value"] = (fact["value"].to_f * 60.0).round(2) if fact["value"].present?
      fact["unit"] = "bpm"
    when "count/min"
      fact["unit"] = "bpm"
    end

    fact
  end

  def self.merge_legacy_payload(payload, facts)
    legacy_items = payload["parseable_data"]
    return facts unless legacy_items.is_a?(Array)

    legacy_texts = if facts.present?
      facts.filter_map { |fact| fact["text"] }
    else
      Array(payload["facts"])
    end

    Entry.build_fact_objects_from_legacy(legacy_texts, legacy_items)
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

  def self.attachment_ocr_retry_prompt(input, entry: nil)
    <<~PROMPT.strip
      #{user_prompt(input, entry: entry)}

      Important attachment handling:
      - The attachment may be a scanned or photographed medical document.
      - OCR the rendered pages carefully.
      - If a lab table, medical letter, invoice, or report is visible, extract the readable facts from it.
      - Do not return an empty facts array when the attachment clearly contains readable medical content.
      - Return empty facts only if the rendered pages truly contain no readable medically useful information.
    PROMPT
  end

  def self.multimodal_models_for(preference)
    [ preference.llm_model ].compact.uniq
  end

  def self.document_payload_useful?(payload)
    sanitize_facts(payload["facts"]).present? || Array(payload["parseable_data"]).present?
  end

  def self.sanitize_parseable_data(value)
    Entry.build_fact_objects_from_legacy([], value).filter_map do |fact|
      Entry.new.send(:legacy_parseable_item_for, fact)
    end
  end

  def self.enrich_healthkit_facts(facts, input, entry: nil)
    return facts unless entry&.respond_to?(:source) && entry.source == Entry::SOURCES[:healthkit]

    enriched = facts.deep_dup
    summary_quality = entry.source_ref.to_s.start_with?("healthkit:month:") || input.to_s.downcase.include?("monthly summary") ? "monthly" : "daily"

    unless enriched.any? { |fact| fact["kind"] == "summary" && fact["value"] == "Apple Health" }
      enriched.unshift({ "text" => "Apple Health #{summary_quality} summary", "kind" => "summary", "value" => "Apple Health", "quality" => summary_quality })
    end

    lines = input.to_s.split("\n").map { |line| line.strip.sub(/\A-\s*/, "").sub(/\.$/, "") }.reject(&:blank?)
    blood_pressure = {}

    lines.each do |line|
      case line
      when /\AWeight (?<value>-?\d+(?:\.\d+)?) (?<unit>kg|lb)\z/i
        append_unique_measurement(enriched, "weight", "Weight", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\AHeight (?<value>-?\d+(?:\.\d+)?) (?<unit>cm|m)\z/i
        append_unique_measurement(enriched, "height", "Height", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\ABody temperature(?: avg)? (?<value>-?\d+(?:\.\d+)?) (?<unit>C|F)\z/i
        append_unique_measurement(enriched, "temperature", "Body temperature", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\A(?:Resting pulse|Walking pulse|Pulse) avg (?<value>-?\d+(?:\.\d+)?) (?<unit>[^;]+)(?:;.*)?\z/i
        append_unique_measurement(enriched, "pulse", "Pulse", Regexp.last_match[:value], Regexp.last_match[:unit])
      when /\ASleep (?<value>-?\d+(?:\.\d+)?) hours(?: across .*?)?\z/i
        append_unique_measurement(enriched, "sleep", "Sleep", Regexp.last_match[:value], "h")
      when /\ABlood pressure systolic avg (?<value>-?\d+(?:\.\d+)?) (?<unit>mmHg)\z/i
        blood_pressure["systolic"] = normalize_value(Regexp.last_match[:value])
        blood_pressure["unit"] = Regexp.last_match[:unit]
      when /\ABlood pressure diastolic avg (?<value>-?\d+(?:\.\d+)?) (?<unit>mmHg)\z/i
        blood_pressure["diastolic"] = normalize_value(Regexp.last_match[:value])
        blood_pressure["unit"] = Regexp.last_match[:unit]
      else
        append_healthkit_pattern_fact(enriched, line)
      end
    end

    if blood_pressure["systolic"].present? && blood_pressure["diastolic"].present? && enriched.none? { |fact| fact["kind"] == "measurement" && fact["metric"] == "blood_pressure" }
      enriched << {
        "text" => "Blood pressure #{blood_pressure['systolic']}/#{blood_pressure['diastolic']} #{blood_pressure['unit'] || 'mmHg'}",
        "kind" => "measurement",
        "metric" => "blood_pressure",
        "systolic" => blood_pressure["systolic"],
        "diastolic" => blood_pressure["diastolic"],
        "unit" => blood_pressure["unit"] || "mmHg"
      }
    end

    enriched
  end

  def self.enrich_healthkit_parseable_data(parseable_data, input, entry: nil)
    enrich_healthkit_facts(Entry.build_fact_objects_from_legacy([], parseable_data), input, entry: entry).filter_map do |fact|
      Entry.new.send(:legacy_parseable_item_for, fact)
    end
  end

  def self.append_healthkit_pattern_fact(enriched, line)
    HEALTHKIT_FACT_PATTERNS.each do |pattern, metric, label|
      match = line.match(pattern)
      next unless match

      append_unique_measurement(enriched, metric, label, match[:value], match[:unit])
      return
    end

    if (match = line.match(/\AWorkouts (?<count>-?\d+(?:\.\d+)?) with (?<minutes>-?\d+(?:\.\d+)?) total minutes\z/i))
      append_unique_measurement(enriched, "workouts", "Workouts", match[:count], "count")
    end

    if (match = line.match(/\AAudio exposure events (?<count>-?\d+(?:\.\d+)?) with (?<minutes>-?\d+(?:\.\d+)?) total minutes\z/i))
      append_unique_measurement(enriched, "audio_exposure_events", "Audio exposure events", match[:count], "count")
    end
  end

  def self.append_unique_measurement(items, metric, label, value, unit)
    return if items.any? { |fact| fact["kind"] == "measurement" && fact["metric"] == metric }

    fact = {
      "text" => [ label, value, unit ].compact.join(" "),
      "kind" => "measurement",
      "metric" => metric,
      "value" => normalize_value(value),
      "unit" => normalize_unit(unit)
    }
    normalize_measurement_fact!(fact)
    items << fact
  end

  def self.fallback_document_input(input, entry)
    extracted = DocumentTextExtractor.extract_many(entry_documents(entry))
    return input if extracted.blank?
    return extracted if input.blank?

    [ input, extracted ].join("\n\n")
  end
end
