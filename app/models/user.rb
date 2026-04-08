class User < ApplicationRecord
  belongs_to :person
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  scope :with_password, -> { where.not(password_digest: [ nil, "" ]) }

  validates :email_address, presence: true, uniqueness: true
  validates :person_id, uniqueness: true
  validates :password, length: { minimum: 12, maximum: 72 }, allow_nil: true
  validates :password_confirmation, presence: true, if: :password_present?
  validate :password_confirmation_matches, if: :password_present?

  before_validation :stamp_password_set_at, if: :password_present?

  def can_administer?
    admin?
  end

  def password_login_enabled?
    password_digest.present?
  end

  private

  def password_present?
    password.present?
  end

  def password_confirmation_matches
    errors.add(:password_confirmation, :confirmation) if password != password_confirmation
  end

  def stamp_password_set_at
    self.password_set_at = Time.current
  end
end
