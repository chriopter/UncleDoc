require "json"
require "net/http"
require "uri"

class LlmChatRequest
  Response = Struct.new(:content, :status_code, :body, keyword_init: true)

  def self.call(request_kind:, preference:, messages:, person: nil, entry: nil, temperature: nil)
    endpoint = "#{preference.llm_api_base.chomp('/')}/chat/completions"
    payload = {
      model: preference.llm_model,
      messages: messages
    }
    payload[:temperature] = temperature unless temperature.nil?

    log = LlmLog.create!(
      person: person,
      entry: entry,
      request_kind: request_kind,
      provider: preference.llm_provider,
      model: preference.llm_model,
      endpoint: endpoint,
      request_payload: JSON.pretty_generate(payload)
    )

    uri = URI.parse(endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{preference.llm_runtime_api_key}" if preference.llm_runtime_api_key.present?
    request.body = payload.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    log.update!(status_code: response.code.to_i, response_body: response.body)

    raise "LLM request failed with status #{response.code}" unless response.code.to_i.between?(200, 299)

    Response.new(
      content: JSON.parse(response.body).dig("choices", 0, "message", "content").to_s,
      status_code: response.code.to_i,
      body: response.body
    )
  rescue StandardError => error
    log&.update!(error_message: error.message, response_body: log.response_body.presence)
    raise
  end
end
