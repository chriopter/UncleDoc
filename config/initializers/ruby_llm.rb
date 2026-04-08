RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
  config.gemini_api_key = ENV["GEMINI_API_KEY"]
  config.openai_api_base = ENV["OPENAI_API_BASE"]
  config.mistral_api_key = ENV["MISTRAL_API_KEY"]
  config.ollama_api_base = ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1")
  config.ollama_api_key = ENV["OLLAMA_API_KEY"]
  config.openai_api_key = ENV["OPENAI_API_KEY"] || ENV["FIREWORKS_API_KEY"]
  config.openai_api_base ||= UserPreference::FIREWORKS_API_BASE if ENV["FIREWORKS_API_KEY"].present?
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
  config.perplexity_api_key = ENV["PERPLEXITY_API_KEY"]
  config.model_registry_class = "LlmModel"
  config.use_new_acts_as = true
  config.xai_api_key = ENV["XAI_API_KEY"]
  config.logger = Rails.logger
end
