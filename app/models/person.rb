class Person < ApplicationRecord
  has_many :entries, dependent: :destroy
  has_many :llm_logs, dependent: :destroy

  validates :name, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :baby_mode, -> { where(baby_mode: true) }

  def last_feeding
    entries.where(
      "EXISTS (SELECT 1 FROM json_each(entries.parseable_data) WHERE json_extract(value, '$.type') IN ('breast_feeding', 'bottle_feeding'))"
    ).recent_first.first
  end

  def last_diaper
    entries.by_parseable_data_type("diaper").recent_first.first
  end

  def last_sleep
    entries.by_parseable_data_type("sleep").recent_first.first
  end

  def time_since_last_feeding
    last_feeding&.display_time
  end

  def last_feeding_started_at
    return baby_feeding_timer_started_at if baby_feeding_timer_started_at.present?

    last_breast_feeding = entries.by_parseable_data_type("breast_feeding").recent_first.first
    return if last_breast_feeding.blank?

    minutes = last_breast_feeding.first_parseable_data_of_type("breast_feeding")&.dig("value").to_i
    return if minutes <= 0

    last_breast_feeding.display_time - minutes.minutes
  end

  def last_feeding_stopped_at
    last_feeding&.display_time
  end

  def last_feeding_duration_minutes
    breast_feeding = entries.by_parseable_data_type("breast_feeding").recent_first.first
    return if breast_feeding.blank?

    minutes = breast_feeding.first_parseable_data_of_type("breast_feeding")&.dig("value").to_i
    minutes.positive? ? minutes : nil
  end

  def recent_timed_feedings(limit = 3)
    entries.by_parseable_data_type("breast_feeding").recent_first.select { |entry| entry.feeding_duration_minutes.to_i.positive? }.first(limit)
  end

  def time_since_last_diaper
    last_diaper&.display_time
  end

  def time_since_last_sleep
    last_sleep&.display_time
  end

  def recent_sleep_sessions(limit = 3)
    entries.by_parseable_data_type("sleep").recent_first.select { |entry| entry.sleep_duration_minutes.to_i.positive? }.first(limit)
  end

  def recent_diapers(limit = 3)
    entries.by_parseable_data_type("diaper").recent_first.first(limit)
  end
end
