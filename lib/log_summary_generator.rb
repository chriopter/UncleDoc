require "json"
require "net/http"
require "uri"

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
    uri = URI.parse("#{preference.llm_api_base.chomp('/')}/chat/completions")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{preference.llm_runtime_api_key}" if preference.llm_runtime_api_key.present?

    request.body = {
      model: preference.llm_model,
      messages: [
        {
          role: "user",
          content: summary_prompt(person, entries)
        }
      ]
    }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    raise "LLM request failed with status #{response.code}" unless response.code.to_i.between?(200, 299)

    body = JSON.parse(response.body)
    body.dig("choices", 0, "message", "content").to_s
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
    parts << entry.note if entry.note.present?
    parts << data_summary(entry) if entry.data.present?
    parts.compact_blank.join(" - ")
  end

  def self.data_summary(entry)
    Array(entry.data).filter_map do |item|
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
