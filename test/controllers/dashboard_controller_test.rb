require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  def fake_pdf_content(text)
    <<~PDF
      %PDF-1.4
      1 0 obj
      << /Type /Catalog /Pages 2 0 R >>
      endobj
      2 0 obj
      << /Type /Pages /Count 1 /Kids [3 0 R] >>
      endobj
      3 0 obj
      << /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << >> >>
      endobj
      4 0 obj
      << /Length 44 >>
      stream
      BT /F1 12 Tf 36 96 Td (#{text}) Tj ET
      endstream
      endobj
      xref
      0 5
      0000000000 65535 f
      0000000010 00000 n
      0000000063 00000 n
      0000000122 00000 n
      0000000226 00000 n
      trailer
      << /Root 1 0 R /Size 5 >>
      startxref
      319
      %%EOF
    PDF
  end

  test "shows the log tab by default" do
    Person.delete_all
    get root_url

    assert_response :success
    assert_select "button", text: /Family/
    assert_select "a[aria-label='Settings']", minimum: 1
  end

  test "shows family member name when people exist" do
    get root_url

    assert_response :success
    assert_includes @response.body, "MyString"
  end

  test "sets locale from user preferences" do
    UserPreference.update_locale("de")

    get root_url

    assert_response :success
    assert_select "a[aria-label='Einstellungen']", minimum: 1

    UserPreference.update_locale("en")
  end

  test "shows log page for person" do
    person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), input: "Mild fever in the evening", facts: [ "Temperature in the evening" ], parseable_data: [])

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_match(/Alice/, @response.body)
    assert_includes @response.body, "Protocol - Alice"
    assert_includes @response.body, "Temperature in the evening"
    assert_includes @response.body, "Mild fever in the evening"
    assert_includes @response.body, "Occurred"
    assert_includes @response.body, "Parsed type"
    assert_includes @response.body, I18n.l(person.entries.first.display_time, format: :long)
    assert_select "input[type='date'][name='date']", 1
    assert_select "select[name='date']", 0
    assert_not_includes @response.body, I18n.t("chat.title", name: person.name)
  end

  test "research page shows the health chat" do
    person = Person.create!(name: "Research Rita", birth_date: Date.new(2024, 1, 1))

    get person_research_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, I18n.t("chat.title", name: person.name)
    assert_includes @response.body, person_chat_path(person_slug: person.name)
    assert_includes @response.body, I18n.t("chat.welcome", name: person.name)
  end

  test "data menu links to log while research stays separate" do
    person = Person.create!(name: "Menu Marta", birth_date: Date.new(2024, 1, 1))

    get person_files_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, person_log_path(person_slug: person.name)
    assert_includes @response.body, person_research_path(person_slug: person.name)
    assert_includes @response.body, I18n.t("nav.data")
    assert_includes @response.body, I18n.t("nav.files")
    assert_includes @response.body, I18n.t("nav.healthkit")
    assert_includes @response.body, I18n.t("nav.research")
  end

  test "shows baby dashboard and ai summary on baby log page" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 9, 0), input: "Bottle 120ml", facts: [ "Bottle feeding 120 ml" ], parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 10, 0), input: "Peter has fever 39.2", parseable_data: [], parse_status: "pending")

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Log for Marlon"
    assert_includes @response.body, "Bottle feeding 120 ml"
    assert_includes @response.body, "Show raw data"
    assert_includes @response.body, "Sending input to the LLM"
  end

  test "overview keeps weight but moves baby-specific widgets to baby tab" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 27, 9, 0), input: "Bottle 120ml", facts: [ "Bottle feeding 120 ml" ], parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 10, 0), input: "Diaper: wet", facts: [ "Diaper wet" ], parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => false } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 6, 0), input: "Sleep 95 min", facts: [ "Sleep 95 min" ], parseable_data: [ { "type" => "sleep", "value" => 95, "unit" => "min" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 15, 0), input: "Gewicht 3356g", facts: [ "Gewicht 3356 g" ], parseable_data: [ { "type" => "weight", "value" => 3356, "unit" => "g" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 31, 9, 0), input: "53cm Körpergröße", facts: [ "Körpergröße 53 cm" ], parseable_data: [ { "type" => "height", "value" => 53, "unit" => "cm" } ])

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Weight trend"
    assert_select "#overview_weight_activity", 1
    assert_select "#overview_baby_tracking_feeding", 0
    assert_select "#overview_baby_tracking_sleep", 0
    assert_select "#overview_baby_tracking_diaper", 0
    assert_select "#overview_baby_activity_feeding", 0
    assert_select "#overview_baby_activity_sleep", 0
    assert_select "#overview_baby_activity_diaper", 0
    assert_select "#overview_height_activity", 0
    assert_select "h2", text: /Protocol - Marlon/, count: 0
  end

  test "shows llm not configured state for skipped parsing" do
    person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), input: "Plain input", parseable_data: [], parse_status: "skipped")

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "LLM parsing is off until a model is configured in Settings."
  end

  test "shows person overview without baby badge by default" do
    person = Person.create!(name: "BabyUser", birth_date: Date.new(2024, 1, 1))

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_select "h2", text: "BabyUser"
    assert_select "span", text: I18n.t("baby.badge"), count: 0
  end

  test "overview updates show parsing state badges" do
    person = Person.create!(name: "Alice", birth_date: Time.zone.local(2024, 1, 1, 12, 0))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), input: "Plain input", parseable_data: [], parse_status: "pending")

    get root_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "1 entry parsing"
  end

  test "recent activity rows expand with input facts and parseable data" do
    person = Person.create!(name: "Christopher", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 31, 10, 0),
      input: "breastfed left side for 18 minutes",
      facts: [ "Breast feeding left 18 min" ],
      parseable_data: [ { "type" => "breast_feeding", "value" => 18, "unit" => "min", "side" => "left" } ]
    )

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Recent Activity"
    assert_includes @response.body, "Breast feeding left 18 min"
    assert_includes @response.body, "Input"
    assert_includes @response.body, "Parsed"
    assert_includes @response.body, "breast_feeding"
  end

  test "recent activity summary clamps long text" do
    person = Person.create!(name: "Clampy", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 31, 9, 0),
      input: "Bla" * 120,
      facts: [],
      parseable_data: []
    )

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "line-clamp-6"
    assert_not_includes @response.body, "line-clamp-2"
  end

  test "overview shows weight widget when weight data exists" do
    person = Person.create!(name: "Weighty", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 27, 9, 0), input: "75kg", facts: [ "Weight 75 kg" ], parseable_data: [ { "type" => "weight", "value" => 75, "unit" => "kg" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 9, 0), input: "74.2kg", facts: [ "Weight 74.2 kg" ], parseable_data: [ { "type" => "weight", "value" => 74.2, "unit" => "kg" } ])

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_select "#overview_weight_activity", 1
    assert_includes @response.body, "Weight trend"
    assert_includes @response.body, "74.2 kg"
  end

  test "overview shows planning widget when appointment and todo data exist" do
    person = Person.create!(name: "Planner", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 10, 0), input: "doctor appointment", facts: [ "Doctor appointment" ], parseable_data: [ { "type" => "appointment", "value" => "doctor appointment", "scheduled_for" => "2026-04-05T10:30:00Z", "location" => "hospital" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 11, 0), input: "todo bring card", facts: [ "Bring vaccination card" ], parseable_data: [ { "type" => "todo", "value" => "bring vaccination card" } ])

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_select "#overview_planning", 1
    assert_includes @response.body, "Appointments &amp; todos"
    assert_includes @response.body, "Appointment"
    assert_includes @response.body, "Todo"
  end

  test "overview appointment and note widgets prefer facts text" do
    person = Person.create!(name: "FactsFirst", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 4, 2, 10, 0),
      input: "doctor appointment",
      facts: [ "Doctor appointment with Dr. Meier" ],
      parseable_data: [ { "type" => "appointment", "value" => "checkup", "location" => "hospital" } ]
    )

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Doctor appointment with Dr. Meier"
    assert_not_includes @response.body, ">checkup<"
  end

  test "overview shows vital widgets" do
    person = Person.create!(name: "Vitals", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 10, 0), input: "37.8 temp", facts: [ "Temperature 37.8 C" ], parseable_data: [ { "type" => "temperature", "value" => 37.8, "unit" => "C" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 11, 0), input: "Pulse 120", facts: [ "Pulse 120 bpm" ], parseable_data: [ { "type" => "pulse", "value" => 120, "unit" => "bpm" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 12, 0), input: "BP 120/80", facts: [ "Blood pressure 120/80 mmHg" ], parseable_data: [ { "type" => "blood_pressure", "systolic" => 120, "diastolic" => 80, "unit" => "mmHg" } ])

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_select "#overview_temperature_activity", 1
    assert_select "#overview_pulse_activity", 1
    assert_select "#overview_blood_pressure_activity", 1
  end

  test "shows dedicated baby page when baby mode enabled" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 6, 0), input: "Sleep 95 min", facts: [ "Sleep 95 min" ], parseable_data: [ { "type" => "sleep", "value" => 95, "unit" => "min" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 15, 0), input: "Gewicht 3356g", facts: [ "Gewicht 3356 g" ], parseable_data: [ { "type" => "weight", "value" => 3356, "unit" => "g" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 31, 9, 0), input: "53cm Körpergröße", facts: [ "Körpergröße 53 cm" ], parseable_data: [ { "type" => "height", "value" => 53, "unit" => "cm" } ])

    get person_baby_url(person_slug: person.name)

    assert_response :success
    assert_select "#overview_baby_tracking_feeding", 1
    assert_select "#overview_baby_tracking_sleep", 1
    assert_select "#overview_baby_tracking_diaper", 1
    assert_select "#overview_baby_activity_feeding", 0
    assert_select "#overview_baby_activity_sleep", 0
    assert_select "#overview_baby_activity_diaper", 0
    assert_select "#overview_weight_activity", 1
    assert_select "#overview_height_activity", 1
  end

  test "overview still shows planning widget when empty" do
    person = Person.create!(name: "EmptyWidgets", birth_date: Date.new(2024, 1, 1))

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_select "#overview_planning", 1
    assert_includes @response.body, "No appointments yet."
    assert_includes @response.body, "No todos yet."
  end

  test "overview and log can sort by entered time" do
    person = Person.create!(name: "Sorty", birth_date: Date.new(2024, 1, 1))
    older_entry = nil
    newer_entry = nil

    travel_to Time.zone.local(2026, 3, 31, 9, 0, 0) do
      older_entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 31, 8, 0, 0), input: "older input", facts: [ "Older fact" ], parseable_data: [])
    end

    travel_to Time.zone.local(2026, 3, 31, 10, 0, 0) do
      newer_entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 8, 0, 0), input: "newer input", facts: [ "Newer fact" ], parseable_data: [])
    end

    get person_overview_url(person_slug: person.name, sort: "entered")
    assert_response :success
    assert @response.body.index("Newer fact") < @response.body.index("Older fact")

    get person_log_url(person_slug: person.name, sort: "entered")
    assert_response :success
    assert @response.body.index("Newer fact") < @response.body.index("Older fact")
  end

  test "files tab lists uploaded documents" do
    person = Person.create!(name: "Filesy", birth_date: Date.new(2024, 1, 1))
    entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "Doctor invoice", facts: [ "Doctor invoice uploaded" ], parseable_data: [])
    entry.documents.attach(io: StringIO.new(fake_pdf_content("Doctor invoice")), filename: "doctor-invoice.pdf", content_type: "application/pdf")

    get person_files_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Files for Filesy"
    assert_includes @response.body, "doctor-invoice.pdf"
    assert_includes @response.body, "Doctor invoice uploaded"
  end

  test "healthkit page shows summary entries and sync state" do
    person = Person.create!(name: "Healthkitty", birth_date: Date.new(2024, 1, 1))
    person.healthkit_syncs.create!(
      device_id: "iphone-main",
      status: "synced",
      last_synced_at: Time.zone.local(2026, 4, 6, 7, 30),
      last_successful_sync_at: Time.zone.local(2026, 4, 6, 7, 30),
      synced_record_count: 42
    )
    person.healthkit_records.create!(
      device_id: "iphone-main",
      external_id: "step-1",
      record_type: "HKQuantityTypeIdentifierStepCount",
      source_name: "Health",
      start_at: Time.zone.local(2026, 4, 5, 8, 0),
      payload: { "quantity" => "4123 count" }
    )
    HealthkitSummarySyncService.call(person:, today: Date.new(2026, 4, 6))

    get person_healthkit_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "HealthKit for Healthkitty"
    assert_includes @response.body, "Summary entries"
    assert_includes @response.body, "Raw data"
    assert_includes @response.body, "iphone-main"
    assert_includes @response.body, "healthkit:day:2026-04-05"
    assert_includes @response.body, "Apple Health daily summary"
    assert_includes @response.body, "Step count 4123 count."
    assert_includes @response.body, "Reset imported data"
  end

  test "healthkit page paginates summary entries" do
    person = Person.create!(name: "PagedKit", birth_date: Date.new(2024, 1, 1))

    25.times do |index|
      person.entries.create!(
        source: Entry::SOURCES[:healthkit],
        source_ref: "healthkit:day:2026-03-#{format('%02d', index + 1)}",
        occurred_at: Time.zone.local(2026, 3, index + 1, 23, 59),
        input: "Apple Health daily summary for March #{index + 1}, 2026.\n- Step count #{index + 1} count.",
        facts: [],
        parseable_data: [],
        parse_status: "parsed"
      )
    end

    get person_healthkit_url(person_slug: person.name, page: 2)

    assert_response :success
    assert_includes @response.body, "Page 2 of 2"
    assert_includes @response.body, "healthkit:day:2026-03-05"
    assert_not_includes @response.body, "healthkit:day:2026-03-25"
  end

  test "healthkit page can switch to raw data view" do
    person = Person.create!(name: "RawKit", birth_date: Date.new(2024, 1, 1))
    person.healthkit_records.create!(
      device_id: "watch-1",
      external_id: "sleep-1",
      record_type: "HKCategoryTypeIdentifierSleepAnalysis",
      source_name: "Health",
      start_at: Time.zone.local(2026, 4, 5, 0, 0),
      end_at: Time.zone.local(2026, 4, 5, 7, 30),
      payload: { "value" => "0" }
    )

    get person_healthkit_url(person_slug: person.name, view: "raw")

    assert_response :success
    assert_includes @response.body, "Raw HealthKit data"
    assert_includes @response.body, "HKCategoryTypeIdentifierSleepAnalysis"
    assert_includes @response.body, "watch-1"
    assert_includes @response.body, "&quot;value&quot;"
  end

  test "log can filter by date and parsed type" do
    person = Person.create!(name: "Filtery", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "Bottle 120ml", facts: [ "Bottle feeding 120 ml" ], parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 9, 0), input: "Diaper wet", facts: [ "Diaper wet" ], parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => false } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 10, 0), input: "Bottle 90ml", facts: [ "Bottle feeding 90 ml" ], parseable_data: [ { "type" => "bottle_feeding", "value" => 90, "unit" => "ml" } ])

    get person_log_url(person_slug: person.name, date: "2026-03-29", parseable_type: "diaper")

    assert_response :success
    assert_includes @response.body, "Diaper wet"
    assert_not_includes @response.body, "Bottle feeding 120 ml"
    assert_not_includes @response.body, "Bottle feeding 90 ml"
    assert_includes @response.body, "2026-03-29"
    assert_includes @response.body, "diaper · Diaper"
  end

  test "baby log can filter by exact parseable type" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 12, 0), input: "Stillen links 12 min; Windel: nass + fest", facts: [ "Stillen links 12 min", "Windel nass und fest" ], parseable_data: [ { "type" => "breast_feeding", "value" => 12, "unit" => "min", "side" => "left" }, { "type" => "diaper", "wet" => true, "solid" => true } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 19, 30), input: "Windel: nass + fest", facts: [ "Windel nass und fest" ], parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => true } ])

    get person_log_url(person_slug: person.name, date: "2026-03-29", parseable_type: "breast_feeding")

    assert_response :success
    assert_includes @response.body, "breast_feeding · Breastfeeding"
    assert_includes @response.body, "Stillen links 12 min"
    assert_not_includes @response.body, "March 29, 2026 19:30"
  end
end
