require "json"
require "net/http"
require "uri"

class LlmModelCatalog
  Result = Struct.new(:models, :error, keyword_init: true)

  def self.lookup(provider:, api_key:, api_base:)
    metadata = AppSetting.provider_metadata(provider)

    return Result.new(models: [], error: :unsupported_provider) unless metadata[:model_lookup] == :openai_compatible
    return Result.new(models: [], error: :missing_api_key) if api_key.blank? && provider != "ollama"
    return Result.new(models: [], error: :missing_api_base) if api_base.blank?

    uri = URI.parse("#{api_base.chomp('/')}/models")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{api_key}" if api_key.present?
    request["Content-Type"] = "application/json"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    return Result.new(models: [], error: :unauthorized) if response.code.to_i == 401
    return Result.new(models: [], error: :request_failed) unless response.code.to_i.between?(200, 299)

    body = JSON.parse(response.body)
    data = body["data"] || body["models"] || []
    models = Array(data).filter_map { |item| item["id"] || item["name"] }.sort

    Result.new(models: models)
  rescue JSON::ParserError, SocketError, IOError, SystemCallError, Timeout::Error, URI::InvalidURIError => error
    Rails.logger.warn("LLM model lookup failed: #{error.class}: #{error.message}")
    Result.new(models: [], error: :request_failed)
  end
end
