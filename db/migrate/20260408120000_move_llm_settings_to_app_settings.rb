class MoveLlmSettingsToAppSettings < ActiveRecord::Migration[8.1]
  class MigrationAppSetting < ApplicationRecord
    self.table_name = "app_settings"

    encrypts :llm_api_key
  end

  class MigrationUserPreference < ApplicationRecord
    self.table_name = "user_preferences"
  end

  def up
    create_table :app_settings do |t|
      t.string :llm_provider
      t.text :llm_api_key
      t.string :llm_model

      t.timestamps
    end

    MigrationAppSetting.reset_column_information
    MigrationUserPreference.reset_column_information

    legacy_preference = MigrationUserPreference.first
    app_setting = MigrationAppSetting.new(
      llm_provider: legacy_preference&.llm_provider.presence || "openai",
      llm_model: legacy_preference&.llm_model
    )

    if legacy_preference&.llm_api_key_ciphertext.present?
      app_setting.llm_api_key = decrypt_legacy_api_key(legacy_preference.llm_api_key_ciphertext)
    end

    app_setting.save!

    remove_column :user_preferences, :llm_provider, :string
    remove_column :user_preferences, :llm_api_key_ciphertext, :text
    remove_column :user_preferences, :llm_model, :string
  end

  def down
    add_column :user_preferences, :llm_provider, :string
    add_column :user_preferences, :llm_api_key_ciphertext, :text
    add_column :user_preferences, :llm_model, :string

    MigrationUserPreference.reset_column_information
    MigrationAppSetting.reset_column_information

    preference = MigrationUserPreference.first_or_create!
    setting = MigrationAppSetting.first

    if setting.present?
      preference.update!(
        llm_provider: setting.llm_provider,
        llm_model: setting.llm_model,
        llm_api_key_ciphertext: encrypt_legacy_api_key(setting.llm_api_key)
      )
    end

    drop_table :app_settings
  end

  private

  def legacy_encryptor
    secret = Rails.application.secret_key_base
    key = ActiveSupport::KeyGenerator.new(secret).generate_key("user-preference-llm-api-key", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def decrypt_legacy_api_key(ciphertext)
    legacy_encryptor.decrypt_and_verify(ciphertext)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def encrypt_legacy_api_key(value)
    return if value.blank?

    legacy_encryptor.encrypt_and_sign(value)
  end
end
