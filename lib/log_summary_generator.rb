require "json"

class LogSummaryGenerator
  Result = Struct.new(:summary, :error, keyword_init: true)

  def self.call(person:, entries:, preference: UserPreference.current)
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
        {
          role: "user",
          content: summary_prompt(person, entries)
        }
      ]
    ).content
  end

  def self.summary_prompt(person, entries)
    <<~PROMPT
      You are helping a family review a health log.

      Person: #{person.name}

      Read the entries below and write a concise summary with:
      - a short overview of the main pattern
      - any notable changes or repeated issues
      - a brief suggestion for what to keep an eye on

      Do not mention that you are an AI. Keep the tone calm and practical.

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
    parts << entry.fact_summary if entry.facts.present?
    parts << entry.input if entry.input.present?
    parts << parseable_data_summary(entry) if entry.parseable_data.present?
    parts.compact_blank.join(" - ")
  end

  def self.parseable_data_summary(entry)
    Array(entry.parseable_data).filter_map do |item|
      next unless item.is_a?(Hash)

      parts = [ item["type"] ]
      value = item["value"]
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
