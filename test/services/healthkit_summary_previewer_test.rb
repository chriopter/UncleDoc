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

    assert_equal 5, previews.size
    assert previews.any? { |preview| preview.source_ref == "healthkit:month:2026-02" }
    assert previews.any? { |preview| preview.source_ref == "healthkit:day:2026-03-01" }
    assert previews.any? { |preview| preview.source_ref == "healthkit:day:2026-04-05" }

    february = previews.find { |preview| preview.source_ref == "healthkit:month:2026-02" }
    assert_includes february.input, "Apple Health monthly summary for February 2026."
    assert_includes february.input, "- Coverage: 1 days with data, 1 raw records."
    assert_includes february.input, "Step count 120 count"
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
    assert_includes preview.input, "Audiogram 1 records"
    assert_includes preview.input, "Activity move mode present (characteristic.activityMoveMode)"
  end

  test "splits overnight durations across touched days" do
    person = Person.create!(name: "Sleep Split", birth_date: Date.new(2020, 1, 1))

    create_record(
      person,
      "HKCategoryTypeIdentifierSleepAnalysis",
      "2026-04-04 23:00:00",
      end_at: "2026-04-05 07:00:00",
      value: "0"
    )

    previews = HealthkitSummaryPreviewer.call(person:, today: Date.new(2026, 4, 6))
    april_fourth = previews.find { |preview| preview.source_ref == "healthkit:day:2026-04-04" }
    april_fifth = previews.find { |preview| preview.source_ref == "healthkit:day:2026-04-05" }

    assert_includes april_fourth.input, "Sleep 1 hours"
    assert_includes april_fifth.input, "Sleep 7 hours"
    assert_equal [ "HKCategoryTypeIdentifierSleepAnalysis" ], april_fifth.present_record_types
  end

  test "keeps summary text in english" do
    person = Person.create!(name: "Localized", birth_date: Date.new(2020, 1, 1))
    create_record(person, "HKQuantityTypeIdentifierStepCount", "2026-04-05 08:00:00", quantity: "4123 count")

    preview = I18n.with_locale(:de) do
      HealthkitSummaryPreviewer.call(person:, today: Date.new(2026, 4, 6)).find { |item| item.source_ref == "healthkit:day:2026-04-05" }
    end

    assert_includes preview.input, "Apple Health daily summary"
    assert_includes preview.input, "- Source: Apple Health."
    assert_includes preview.input, "Step count 4123 count"
  end

  test "ignores malformed payload shapes without crashing" do
    person = Person.create!(name: "Malformed", birth_date: Date.new(2020, 1, 1))

    HealthkitRecord.create!(
      person: person,
      device_id: "device-a",
      external_id: "bad-payload",
      record_type: "HKDataTypeIdentifierAudiogram",
      source_name: "Health",
      start_at: Time.zone.parse("2026-04-05 12:00:00"),
      payload: "[]"
    )

    preview = HealthkitSummaryPreviewer.call(person:, today: Date.new(2026, 4, 6)).find do |item|
      item.source_ref == "healthkit:day:2026-04-05"
    end

    assert_equal [], preview.missing_record_types
    assert_includes preview.input, "Audiogram"
  end

  test "normalizes heart rate units to bpm in summaries" do
    person = Person.create!(name: "Pulse Units", birth_date: Date.new(2020, 1, 1))

    create_record(person, "HKQuantityTypeIdentifierHeartRate", "2026-04-05 08:00:00", quantity: "1.5 count/s")
    create_record(person, "HKQuantityTypeIdentifierRestingHeartRate", "2026-04-05 09:00:00", quantity: "1.1 count/s")
    create_record(person, "HKQuantityTypeIdentifierWalkingHeartRateAverage", "2026-04-05 10:00:00", quantity: "90 count/min")

    preview = HealthkitSummaryPreviewer.call(person:, today: Date.new(2026, 4, 6)).find do |item|
      item.source_ref == "healthkit:day:2026-04-05"
    end

    assert_includes preview.input, "Pulse avg 90 bpm; min 90; max 90"
    assert_includes preview.input, "Resting pulse avg 66 bpm; min 66; max 66"
    assert_includes preview.input, "Walking pulse avg 90 bpm; min 90; max 90"
    refute_includes preview.input, "count/s"
    refute_includes preview.input, "count/min"
  end

  test "normalizes mixed monthly units before aggregation" do
    person = Person.create!(name: "Monthly Units", birth_date: Date.new(2020, 1, 1))

    create_record(person, "HKQuantityTypeIdentifierHeartRate", "2026-02-10 08:00:00", quantity: "84 count/min")
    create_record(person, "HKQuantityTypeIdentifierHeartRate", "2026-02-11 08:00:00", quantity: "1.4 count/s")
    create_record(person, "HKQuantityTypeIdentifierBodyMass", "2026-02-10 09:00:00", quantity: "94000 g")
    create_record(person, "HKQuantityTypeIdentifierBodyMass", "2026-02-11 09:00:00", quantity: "94 kg")
    create_record(person, "HKQuantityTypeIdentifierRestingHeartRate", "2026-03-01 08:00:00", quantity: "1 count/s")

    preview = HealthkitSummaryPreviewer.call(person:, today: Date.new(2026, 4, 6)).find do |item|
      item.source_ref == "healthkit:month:2026-02"
    end

    assert_includes preview.input, "Pulse avg 84 bpm; min 84; max 84"
    assert_includes preview.input, "Weight avg 94 kg; min 94; max 94"
    refute_includes preview.input, "94000 kg"
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
