require "json"

class LlmChatRequest
  Response = Struct.new(:content, :status_code, :body, keyword_init: true)

  def self.call(request_kind:, preference:, messages:, person: nil, entry: nil, temperature: nil)
    chat = ResearchChatRuntime.build_chat(setting: preference, temperature:)
    Array(messages).each do |message|
      chat.add_message(role: message.fetch(:role), content: message.fetch(:content))
    end

    response = chat.complete
    raw = response.raw

    Response.new(
      content: response.content.to_s,
      status_code: raw_status(raw),
      body: raw_body(raw)
    )
  end

  def self.raw_status(raw)
    raw.respond_to?(:status) ? raw.status : nil
  end

  def self.raw_body(raw)
    body = if raw.respond_to?(:body)
      raw.body
    elsif raw.respond_to?(:to_h)
      raw.to_h
    else
      raw
    end

    body.is_a?(String) ? body.to_s.dup.force_encoding("UTF-8").scrub : body&.to_json
  end
end
