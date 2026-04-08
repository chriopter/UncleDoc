class UserDevice < ApplicationRecord
  IOS_PLATFORM = "ios".freeze
  DEFAULT_NAME = "UncleDoc iOS".freeze

  belongs_to :user

  validates :platform, presence: true
  validates :token_digest, uniqueness: true, allow_nil: true

  encrypts :token

  scope :active, -> { where(revoked_at: nil) }

  def self.authenticate_token(token)
    return if token.blank?

    active.find_by(token_digest: digest_token(token))
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token)
  end

  def ensure_token!
    return token if token.present? && token_digest.present?

    fresh_token = SecureRandom.urlsafe_base64(48)
    update!(
      token: fresh_token,
      token_digest: self.class.digest_token(fresh_token),
      token_generated_at: Time.current,
      revoked_at: nil
    )
    fresh_token
  end

  def touch_token_usage!
    update_column(:last_used_at, Time.current)
  end
end
