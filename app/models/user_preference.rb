class UserPreference < ApplicationRecord
  FIREWORKS_API_BASE = "https://api.fireworks.ai/inference/v1".freeze
  OPENAI_API_BASE = "https://api.openai.com/v1".freeze
  OPENROUTER_API_BASE = "https://openrouter.ai/api/v1".freeze
  XAI_API_BASE = "https://api.x.ai/v1".freeze
  MISTRAL_API_BASE = "https://api.mistral.ai/v1".freeze
  PERPLEXITY_API_BASE = "https://api.perplexity.ai".freeze
  DEEPSEEK_API_BASE = "https://api.deepseek.com/v1".freeze
  OLLAMA_API_BASE = "http://localhost:11434/v1".freeze

  DEFAULTS = {
    locale: "en",
    date_format: "long",
    llm_provider: "openai"
  }.freeze

  LLM_PROVIDERS = {
    "openai" => { env_key: "OPENAI_API_KEY", env_base_key: "OPENAI_API_BASE", api_base: OPENAI_API_BASE, model_lookup: :openai_compatible },
    "fireworks" => { env_key: "FIREWORKS_API_KEY", api_base: FIREWORKS_API_BASE, ruby_llm_provider: :openai, model_lookup: :openai_compatible },
    "anthropic" => { env_key: "ANTHROPIC_API_KEY", model_lookup: :unsupported },
    "gemini" => { env_key: "GEMINI_API_KEY", model_lookup: :unsupported },
    "openrouter" => { env_key: "OPENROUTER_API_KEY", env_base_key: "OPENROUTER_API_BASE", api_base: OPENROUTER_API_BASE, model_lookup: :openai_compatible },
    "ollama" => { env_key: "OLLAMA_API_KEY", env_base_key: "OLLAMA_API_BASE", api_base: OLLAMA_API_BASE, model_lookup: :openai_compatible },
    "xai" => { env_key: "XAI_API_KEY", api_base: XAI_API_BASE, model_lookup: :openai_compatible },
    "mistral" => { env_key: "MISTRAL_API_KEY", api_base: MISTRAL_API_BASE, model_lookup: :openai_compatible },
    "perplexity" => { env_key: "PERPLEXITY_API_KEY", api_base: PERPLEXITY_API_BASE, model_lookup: :openai_compatible },
    "deepseek" => { env_key: "DEEPSEEK_API_KEY", env_base_key: "DEEPSEEK_API_BASE", api_base: DEEPSEEK_API_BASE, model_lookup: :openai_compatible }
  }.freeze

  validates :locale, inclusion: { in: %w[en de] }, allow_nil: true
  validates :date_format, inclusion: { in: %w[long compact] }, allow_nil: true
  validates :llm_provider, inclusion: { in: LLM_PROVIDERS.keys }, allow_nil: true

  def self.current
    preference = first_or_create(DEFAULTS)
    missing_defaults = DEFAULTS.each_with_object({}) do |(attribute, value), updates|
      updates[attribute] = value if preference.public_send(attribute).blank?
    end

    preference.update!(missing_defaults) if missing_defaults.any?
    preference
  end

  def self.update_locale(locale)
    preference = current
    preference.update!(locale: locale) if %w[en de].include?(locale)
    preference
  end

  def self.update_date_format(date_format)
    preference = current
    preference.update!(date_format: date_format) if %w[long compact].include?(date_format)
    preference
  end

  def self.update_llm_provider(llm_provider)
    preference = current
    preference.update!(llm_provider: llm_provider) if LLM_PROVIDERS.key?(llm_provider)
    preference
  end

  def self.update_llm_settings(llm_provider:, llm_api_key: nil, llm_model: nil)
    preference = current
    previous_provider = preference.llm_provider
    preference.llm_provider = llm_provider if LLM_PROVIDERS.key?(llm_provider)
    preference.llm_api_key = llm_api_key if llm_api_key.present?
    preference.llm_model = llm_model.presence if llm_model.present?
    preference.llm_model = nil if llm_provider.present? && previous_provider != llm_provider && llm_model.blank?
    preference.save! if preference.changed?
    preference
  end

  def self.provider_metadata(provider)
    LLM_PROVIDERS.fetch(provider)
  end

  def llm_api_key
    return if llm_api_key_ciphertext.blank?

    self.class.encryptor.decrypt_and_verify(llm_api_key_ciphertext)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def llm_api_key=(value)
    self.llm_api_key_ciphertext = value.present? ? self.class.encryptor.encrypt_and_sign(value) : nil
  end

  def llm_api_key_configured?
    llm_api_key_ciphertext.present?
  end

  def llm_runtime_api_key
    llm_api_key.presence || ENV[llm_env_key]
  end

  def llm_env_key
    self.class.provider_metadata(llm_provider).fetch(:env_key)
  end

  def llm_api_base
    metadata = self.class.provider_metadata(llm_provider)
    metadata[:env_base_key].present? ? ENV[metadata[:env_base_key]].presence || metadata[:api_base] : metadata[:api_base]
  end

  def llm_model_lookup_supported?
    self.class.provider_metadata(llm_provider)[:model_lookup] == :openai_compatible
  end

  def llm_openai_compatible?
    llm_model_lookup_supported?
  end

  def llm_ruby_provider
    (self.class.provider_metadata(llm_provider)[:ruby_llm_provider] || llm_provider).to_sym
  end

  def self.encryptor
    secret = Rails.application.secret_key_base
    key = ActiveSupport::KeyGenerator.new(secret).generate_key("user-preference-llm-api-key", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end
end
