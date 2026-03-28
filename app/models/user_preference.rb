class UserPreference < ApplicationRecord
  validates :locale, inclusion: { in: %w[en de] }, allow_nil: true
  validates :date_format, inclusion: { in: %w[long compact] }, allow_nil: true

  def self.current
    first_or_create(
      locale: "en",
      date_format: "long"
    )
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
