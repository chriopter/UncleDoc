require "test_helper"

class HealthkitSummarySyncServiceTest < ActiveSupport::TestCase
  test "creates summary entries and removes stale healthkit entries" do
    preference = AppSetting.current
    original_provider = preference.llm_provider
    original_model = preference.llm_model
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    person = Person.create!(name: "Sync Service", birth_date: Date.new(2020, 1, 1))
    person.entries.create!(
      source: Entry::SOURCES[:healthkit],
      source_ref: "healthkit:month:2025-01",
      occurred_at: Time.zone.local(2025, 1, 31, 23, 59),
      input: "Old summary",
      facts: [],
      parseable_data: [],
      parse_status: "parsed"
    )

    person.healthkit_records.create!(
      device_id: "device-a",
      external_id: "step-1",
      record_type: "HKQuantityTypeIdentifierStepCount",
      source_name: "Health",
      start_at: Time.zone.local(2026, 4, 5, 8, 0),
      payload: { "quantity" => "4123 count" }
    )

    result = nil
    assert_difference("person.entries.where(source: 'healthkit').count", 0) do
      result = HealthkitSummarySyncService.call(person:, today: Date.new(2026, 4, 6))
    end

    assert_equal 1, result.created_count
    assert_equal 0, result.updated_count
    assert_equal 1, result.deleted_count

    entry = person.entries.find_by!(source_ref: "healthkit:day:2026-04-05")
    assert_equal Entry::SOURCES[:healthkit], entry.source
    assert_equal "pending", entry.parse_status
    assert_includes entry.input, "Apple Health daily summary"
    assert_nil person.entries.find_by(source_ref: "healthkit:month:2025-01")
  ensure
    preference.update!(llm_provider: original_provider, llm_model: original_model)
  end

  test "updates existing monthly summary entries when preview changes" do
    preference = AppSetting.current
    original_provider = preference.llm_provider
    original_model = preference.llm_model
    preference.update!(llm_provider: "ollama", llm_model: "llama3")

    person = Person.create!(name: "Monthly Refresh", birth_date: Date.new(2020, 1, 1))
    entry = person.entries.create!(
      source: Entry::SOURCES[:healthkit],
      source_ref: "healthkit:month:2025-01",
      occurred_at: Time.zone.local(2025, 1, 31, 23, 59),
      input: "Old monthly summary",
      facts: [],
      parseable_data: [],
      parse_status: "parsed"
    )

    person.healthkit_records.create!(
      device_id: "device-a",
      external_id: "step-1",
      record_type: "HKQuantityTypeIdentifierStepCount",
      source_name: "Health",
      start_at: Time.zone.local(2025, 1, 15, 8, 0),
      payload: { "quantity" => "4123 count" }
    )
    person.healthkit_records.create!(
      device_id: "device-a",
      external_id: "step-2",
      record_type: "HKQuantityTypeIdentifierRestingHeartRate",
      source_name: "Health",
      start_at: Time.zone.local(2025, 2, 1, 8, 0),
      payload: { "quantity" => "60 count/min" }
    )

    result = HealthkitSummarySyncService.call(person:, today: Date.new(2025, 3, 5))

    assert_equal 1, result.created_count
    assert_equal 1, result.updated_count
    assert_equal 0, result.deleted_count

    entry.reload
    assert_includes entry.input, "Apple Health monthly summary for January 2025"
    assert_equal "pending", entry.parse_status
    assert person.entries.find_by(source_ref: "healthkit:day:2025-02-01")
  ensure
    preference.update!(llm_provider: original_provider, llm_model: original_model)
  end
end
