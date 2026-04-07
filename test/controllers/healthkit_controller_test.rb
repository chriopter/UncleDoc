require "test_helper"

class HealthkitControllerTest < ActionDispatch::IntegrationTest
  test "status returns the requested device sync when device_id is provided" do
    person = Person.create!(name: "Multi Device", birth_date: Date.new(2024, 3, 10))
    older_sync = HealthkitSync.create!(
      person: person,
      device_id: "device-a",
      status: "failed",
      last_error: "Old error",
      synced_record_count: 3,
      last_synced_at: 2.days.ago,
      updated_at: 2.days.ago
    )
    requested_sync = HealthkitSync.create!(
      person: person,
      device_id: "device-b",
      status: "synced",
      synced_record_count: 11,
      last_synced_at: 1.hour.ago,
      last_successful_sync_at: 1.hour.ago,
      updated_at: 1.hour.ago,
      details: { phase: "foreground" }
    )

    get "/ios/healthkit/status", params: { person_uuid: person.uuid, device_id: requested_sync.device_id }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal requested_sync.status, payload.dig("sync", "status")
    assert_equal requested_sync.synced_record_count, payload.dig("sync", "synced_record_count")
    assert_equal({ "phase" => "foreground" }, payload.dig("sync", "details"))
    assert_not_equal older_sync.last_error, payload.dig("sync", "last_error")
  end

  test "status falls back to the latest sync when device_id is omitted" do
    person = Person.create!(name: "Latest Sync", birth_date: Date.new(2024, 3, 10))
    HealthkitSync.create!(person: person, device_id: "device-a", status: "failed", updated_at: 2.days.ago)
    latest_sync = HealthkitSync.create!(person: person, device_id: "device-b", status: "synced", synced_record_count: 8, updated_at: 1.minute.ago)

    get "/ios/healthkit/status", params: { person_uuid: person.uuid }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal latest_sync.status, payload.dig("sync", "status")
    assert_equal latest_sync.synced_record_count, payload.dig("sync", "synced_record_count")
  end

  test "reset clears all device syncs and records for the person" do
    person = Person.create!(name: "Reset Target", birth_date: Date.new(2024, 3, 10))
    other_person = Person.create!(name: "Keep Me", birth_date: Date.new(2024, 3, 11))

    HealthkitSync.create!(person: person, device_id: "device-a", status: "synced")
    HealthkitSync.create!(person: person, device_id: "device-b", status: "failed")
    HealthkitSync.create!(person: other_person, device_id: "device-c", status: "synced")

    HealthkitRecord.create!(person: person, device_id: "device-a", external_id: "record-a", record_type: "sleep", start_at: 1.day.ago)
    HealthkitRecord.create!(person: person, device_id: "device-b", external_id: "record-b", record_type: "sleep", start_at: 2.days.ago)
    HealthkitRecord.create!(person: other_person, device_id: "device-c", external_id: "record-c", record_type: "sleep", start_at: 3.days.ago)

    assert_difference("HealthkitSync.count", -2) do
      assert_difference("HealthkitRecord.count", -2) do
        delete "/ios/healthkit/reset", params: { person_uuid: person.uuid }, as: :json
      end
    end

    assert_response :success
    assert_equal 0, person.healthkit_syncs.count
    assert_equal 0, person.healthkit_records.count
    assert_equal 1, other_person.healthkit_syncs.count
    assert_equal 1, other_person.healthkit_records.count
  end

  test "status stays synced for display after a successful sync" do
    person = Person.create!(name: "Display Sync", birth_date: Date.new(2024, 3, 10))
    sync = HealthkitSync.create!(
      person: person,
      device_id: "device-a",
      status: "syncing",
      last_synced_at: 5.minutes.ago,
      last_successful_sync_at: 10.minutes.ago,
      synced_record_count: 99
    )

    get "/ios/healthkit/status", params: { person_uuid: person.uuid, device_id: sync.device_id }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "synced", payload.dig("sync", "status")
  end
end
