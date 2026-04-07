class HealthkitSummarySyncJob < ApplicationJob
  queue_as :default

  def perform(person_id, today: nil)
    person = Person.find_by(id: person_id)
    return unless person

    HealthkitSummarySyncService.call(person:, today: today ? Date.parse(today.to_s) : Time.zone.today)
  rescue ArgumentError
    HealthkitSummarySyncService.call(person:, today: Time.zone.today)
  end
end
