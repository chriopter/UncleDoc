require "json"

class LogSummaryGenerator
  Result = Struct.new(:summary, :error, keyword_init: true)

  def self.call(person:, entries:, preference: AppSetting.current)
    return Result.new(error: :missing_model) if preference.llm_model.blank?
    return Result.new(error: :missing_api_key) if preference.llm_runtime_api_key.blank? && preference.llm_ruby_provider != :ollama
    return Result.new(error: :no_entries) if entries.blank?
    return Result.new(error: :unsupported_provider) unless preference.llm_openai_compatible?

    Result.new(summary: request_summary(person, entries, preference))
  rescue StandardError => error
    Rails.logger.warn("Log summary failed: #{error.class}: #{error.message}")
    Result.new(error: :request_failed)
  end

  def self.request_summary(person, entries, preference)
    LlmChatRequest.call(
      request_kind: "log_summary",
      preference: preference,
      person: person,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: summary_prompt(person, entries) }
      ]
    ).content
  end

  def self.system_prompt
    File.read(Rails.root.join("prompts/uncledoc.md"))
  end

  def self.summary_prompt(person, entries)
    <<~PROMPT
      Person: #{person.name}

      Entries:
      #{formatted_entries(entries)}
    PROMPT
  end

  def self.formatted_entries(entries)
    entries.map do |entry|
      "- #{I18n.l(entry.occurred_at, format: :long)}: #{entry_summary(entry)}"
    end.join("\n")
  end

  def self.entry_summary(entry)
    parts = []
    parts << entry.fact_summary if entry.fact_items.present?
    parts << entry.input if entry.input.present?
    parts << fact_object_summary(entry) if entry.fact_objects.present?
    parts.compact_blank.join(" - ")
  end

  def self.fact_object_summary(entry)
    Array(entry.fact_objects).filter_map do |item|
      next unless item.is_a?(Hash)

      parts = [ item["kind"], item["metric"] ].compact
      value = item["value"] || item["result"]
      unit = item["unit"]
      parts << [ value, unit ].compact.join(" ") if value.present?
      parts << item["dose"] if item["dose"].present?
      parts << "wet" if item["wet"] == true
      parts << "solid" if item["solid"] == true
      parts << "rash" if item["rash"] == true
      parts << item["flag"] if item["flag"].present?
      parts.compact.join(" ")
    end.join(", ")
  end
end
