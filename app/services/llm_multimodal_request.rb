require "json"

class LlmMultimodalRequest
  Response = Struct.new(:content, :status_code, :body, keyword_init: true)

  def self.call(request_kind:, preference:, instructions:, prompt:, attachments:, person: nil, entry: nil, temperature: nil)
    sync_ruby_llm_config!(preference)

    log = LlmLog.create!(
      person: person,
      entry: entry,
      request_kind: request_kind,
      provider: preference.llm_provider,
      model: preference.llm_model,
      endpoint: "#{preference.llm_api_base.chomp('/')}/chat/completions",
      request_payload: JSON.pretty_generate({
        model: preference.llm_model,
        provider: preference.llm_provider,
        instructions: instructions,
        prompt: prompt,
        attachments: Array(attachments).map { |attachment| attachment_payload(attachment) }
      })
    )

    chat = RubyLLM.chat(model: preference.llm_model, provider: preference.llm_ruby_provider, assume_model_exists: true)
                  .with_instructions(instructions)
    chat = chat.with_temperature(temperature) unless temperature.nil?

    response = chat.ask(prompt, with: attachments)
    body = response.content.to_s

    log.update!(status_code: 200, response_body: body)

    Response.new(content: body, status_code: 200, body: body)
  rescue StandardError => error
    log&.update!(error_message: error.message, response_body: log.response_body.presence)
    raise
  end

  def self.sync_ruby_llm_config!(preference)
    config = RubyLLM.config

    case preference.llm_ruby_provider
    when :openai
      config.openai_api_key = preference.llm_runtime_api_key
      config.openai_api_base = preference.llm_api_base
    when :openrouter
      config.openrouter_api_key = preference.llm_runtime_api_key
      config.openrouter_api_base = preference.llm_api_base
    when :ollama
      config.ollama_api_key = preference.llm_runtime_api_key
      config.ollama_api_base = preference.llm_api_base
    when :mistral
      config.mistral_api_key = preference.llm_runtime_api_key
    when :perplexity
      config.perplexity_api_key = preference.llm_runtime_api_key
    when :xai
      config.xai_api_key = preference.llm_runtime_api_key
    when :deepseek
      config.deepseek_api_key = preference.llm_runtime_api_key
    end
  end

  def self.attachment_payload(attachment)
    source = attachment.respond_to?(:blob) ? attachment.blob : attachment

    {
      filename: source.respond_to?(:filename) ? source.filename.to_s : attachment.try(:original_filename),
      content_type: source.respond_to?(:content_type) ? source.content_type : nil,
      byte_size: source.respond_to?(:byte_size) ? source.byte_size : nil
    }.compact
  end
end
