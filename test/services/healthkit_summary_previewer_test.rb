require "test_helper"

class HealthkitSummaryPreviewerTest < ActiveSupport::TestCase
  test "builds previous and current month dailies plus older monthly previews" do
    person = Person.create!(name: "Health Summary", birth_date: Date.new(2020, 1, 1))

    create_record(person, "HKQuantityTypeIdentifierStepCount", "2026-02-10 08:00:00", quantity: "120 count")
    create_record(person, "HKQuantityTypeIdentifierBodyMass", "2026-03-01 09:00:00", quantity: "70 kg")
    create_record(person, "HKQuantityTypeIdentifierHeartRate", "2026-03-31 21:00:00", quantity: "80 count/min")
    create_record(person, "HKCategoryTypeIdentifierSleepAnalysis", "2026-04-01 00:00:00", end_at: "2026-04-01 07:30:00", value: "0")
    create_record(person, "HKDataTypeIdentifierAudiogram", "2026-04-05 12:00:00")

    previews = HealthkitSummaryPreviewer.call(person:, today: Date.new(2026, 4, 6))

    assert_equal 37, previews.size
    assert previews.any? { |preview| preview.source_ref == "healthkit:month:2026-02" }
    assert previews.any? { |preview| preview.source_ref == "healthkit:day:2026-03-15" }
    assert previews.any? { |preview| preview.source_ref == "healthkit:day:2026-04-05" }

    february = previews.find { |preview| preview.source_ref == "healthkit:month:2026-02" }
    assert_includes february.input, "Coverage: 19 daily summaries"
    assert_includes february.input, "Step count 120 count"

    empty_day = previews.find { |preview| preview.source_ref == "healthkit:day:2026-03-15" }
    assert_equal [], empty_day.present_record_types
    assert_includes empty_day.input, "No HealthKit data was recorded for this day"
  end

  test "mentions all present record types in preview text" do
    person = Person.create!(name: "Coverage Check", birth_date: Date.new(2020, 1, 1))

    create_record(person, "HKQuantityTypeIdentifierStepCount", "2026-04-05 08:00:00", quantity: "4123 count")
    create_record(person, "HKDataTypeIdentifierAudiogram", "2026-04-05 12:00:00")
    create_record(person, "characteristic.activityMoveMode", "2026-04-05 12:05:00")

    preview = HealthkitSummaryPreviewer.call(person:, today: Date.new(2026, 4, 6)).find do |item|
      item.source_ref == "healthkit:day:2026-04-05"
    end

    assert_equal [], preview.missing_record_types
    assert_includes preview.input, "Step count 4123 count"
    assert_includes preview.input, "Audiogram 1 record"
    assert_includes preview.input, "Activity move mode (characteristic.activityMoveMode)"
  end

  private

  def create_record(person, record_type, start_at, quantity: nil, value: nil, end_at: nil, source_name: "Health")
    payload = {}
    payload["quantity"] = quantity if quantity
    payload["value"] = value if value

    HealthkitRecord.create!(
      person: person,
      device_id: "device-a",
      external_id: "#{record_type}-#{start_at}",
      record_type: record_type,
      source_name: source_name,
      start_at: Time.zone.parse(start_at),
      end_at: end_at ? Time.zone.parse(end_at) : nil,
      payload: payload
    )
  end
end
