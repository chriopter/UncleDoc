class ResearchChatRuntime
  def self.configuration_error_for(setting)
    return :missing_model if setting.llm_model.blank?
    return :missing_api_key if setting.llm_runtime_api_key.blank? && setting.llm_ruby_provider != :ollama

    nil
  end

  def self.prepare!(chat, setting: AppSetting.current)
    chat.context = context_for(setting)

    if chat.new_record?
      chat.assume_model_exists = true
      chat.model = setting.llm_model
      chat.provider = setting.llm_ruby_provider
      chat.save!
    elsif chat.model_id != setting.llm_model || chat.provider.to_s != setting.llm_ruby_provider.to_s
      chat.assume_model_exists = true
      chat.with_model(setting.llm_model, provider: setting.llm_ruby_provider, assume_exists: true)
    end

    chat
  end

  def self.build_chat(setting: AppSetting.current, model: nil, temperature: nil)
    chat = context_for(setting).chat(
      model: model || setting.llm_model,
      provider: setting.llm_ruby_provider,
      assume_model_exists: true
    )
    chat.with_temperature(temperature) unless temperature.nil?

    headers_for(setting).then do |headers|
      chat.with_headers(**headers) if headers.present?
    end

    chat
  end

  def self.headers_for(setting)
    return {} unless setting.llm_provider == "openrouter"

    {
      "HTTP-Referer" => "http://localhost:3000",
      "X-Title" => "UncleDoc"
    }
  end

  def self.context_for(setting)
    RubyLLM.context do |config|
      config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
      config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
      config.gemini_api_key = ENV["GEMINI_API_KEY"]
      config.mistral_api_key = ENV["MISTRAL_API_KEY"]
      config.ollama_api_base = ENV.fetch("OLLAMA_API_BASE", AppSetting::OLLAMA_API_BASE)
      config.ollama_api_key = ENV["OLLAMA_API_KEY"]
      config.openai_api_key = ENV["OPENAI_API_KEY"]
      config.openai_api_base = ENV["OPENAI_API_BASE"]
      config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
      config.perplexity_api_key = ENV["PERPLEXITY_API_KEY"]
      config.xai_api_key = ENV["XAI_API_KEY"]
      config.logger = Rails.logger
      config.use_new_acts_as = true

      case setting.llm_ruby_provider
      when :openai
        config.openai_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
        config.openai_api_base = setting.llm_api_base if setting.llm_api_base.present?
      when :anthropic
        config.anthropic_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
      when :gemini
        config.gemini_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
      when :mistral
        config.mistral_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
      when :ollama
        config.ollama_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
        config.ollama_api_base = setting.llm_api_base if setting.llm_api_base.present?
      when :openrouter
        config.openrouter_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
      when :perplexity
        config.perplexity_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
      when :xai
        config.xai_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
      when :deepseek
        config.deepseek_api_key = setting.llm_runtime_api_key if setting.llm_runtime_api_key.present?
      end
    end
  end
end
