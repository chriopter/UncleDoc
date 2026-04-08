require "openssl"

secret = Rails.application.secret_key_base
credentials = Rails.application.credentials
encryption_credentials = credentials.respond_to?(:dig) ? credentials.dig(:active_record_encryption) : nil

Rails.application.config.active_record.encryption.primary_key = [
  ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
    encryption_credentials&.dig(:primary_key).presence ||
    OpenSSL::HMAC.hexdigest("SHA256", secret, "active_record_encryption.primary_key")
]

Rails.application.config.active_record.encryption.deterministic_key =
  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
  encryption_credentials&.dig(:deterministic_key).presence ||
  OpenSSL::HMAC.hexdigest("SHA256", secret, "active_record_encryption.deterministic_key")

Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
  encryption_credentials&.dig(:key_derivation_salt).presence ||
  OpenSSL::HMAC.hexdigest("SHA256", secret, "active_record_encryption.key_derivation_salt")
