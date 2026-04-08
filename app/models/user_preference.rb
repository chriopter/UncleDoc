class UserPreference < ApplicationRecord
  DEFAULTS = {
    locale: "en",
    date_format: "long"
  }.freeze

  validates :locale, inclusion: { in: %w[en de] }, allow_nil: true
  validates :date_format, inclusion: { in: %w[long compact] }, allow_nil: true

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
end
