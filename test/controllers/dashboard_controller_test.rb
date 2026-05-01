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
    get root_url

    assert_response :success
    assert_includes @response.body, "MyString"
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
    assert_select "details[data-entry-collapsible='true']", 1
    assert_select "details[data-entry-collapsible='true'] summary"
    assert_select "input[type='date'][name='date']", 1
    assert_select "select[name='date']", 0
    assert_not_includes @response.body, I18n.t("chat.title", name: person.name)
  end

  test "person root shows the cockpit chat" do
    person = Person.create!(name: "Research Rita", birth_date: Date.new(2024, 1, 1))

    get person_root_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, I18n.t("chat.title", name: person.name)
    assert_includes @response.body, I18n.t("dashboard.cockpit.tabs.chat")
    assert_includes @response.body, I18n.t("dashboard.cockpit.tabs.overview")
    assert_includes @response.body, person_chat_path(person_slug: person.name)
    assert_includes @response.body, I18n.t("chat.welcome", name: person.name)
    assert_select "#chat_messages", 1
    assert_select "#research_chat_form", 1
    assert_select "#overview_planning", 0
    assert_not_includes @response.body, I18n.t("chat.system_prompt_label")
  end

  test "cockpit shows persisted chat history when present" do
    person = Person.create!(name: "History Hanna", birth_date: Date.new(2024, 1, 1))
    chat = person.build_chat
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)
    chat.add_message(role: :user, content: "Old question")
    chat.add_message(role: :assistant, content: "Old answer")

    get person_root_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Old question"
    assert_includes @response.body, "Old answer"
    assert_not_includes @response.body, I18n.t("chat.welcome", name: person.name)
  end

  test "data menu links to log while cockpit owns research" do
    person = Person.create!(name: "Menu Marta", birth_date: Date.new(2024, 1, 1))

    get person_files_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, person_log_path(person_slug: person.name)
    assert_includes @response.body, person_root_path(person_slug: person.name)
    assert_includes @response.body, I18n.t("nav.data")
    assert_includes @response.body, I18n.t("nav.files")
    assert_not_includes @response.body, I18n.t("nav.summary")
  end

  test "shows baby dashboard and ai summary on baby log page" do
    person = Person.create!(name: "Demo Mila", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 9, 0), input: "Bottle 120ml", facts: [ "Bottle feeding 120 ml" ], parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 10, 0), input: "Peter has fever 39.2", parseable_data: [], parse_status: "pending")

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, I18n.t("dashboard.protocol.title", name: person.name)
    assert_includes @response.body, "Bottle feeding 120 ml"
    assert_includes @response.body, "Show raw data"
    assert_includes @response.body, I18n.t("entries.tags.pending")
    assert_select "details[data-entry-collapsible='true']", minimum: 2
  end

  test "cockpit keeps weight but moves baby-specific widgets to baby tab" do
    person = Person.create!(name: "Demo Mila", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 27, 9, 0), input: "Bottle 120ml", facts: [ "Bottle feeding 120 ml" ], parseable_data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 10, 0), input: "Diaper: wet", facts: [ "Diaper wet" ], parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => false } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 6, 0), input: "Sleep 95 min", facts: [ "Sleep 95 min" ], parseable_data: [ { "type" => "sleep", "value" => 95, "unit" => "min" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 15, 0), input: "Gewicht 3356g", facts: [ "Gewicht 3356 g" ], parseable_data: [ { "type" => "weight", "value" => 3356, "unit" => "g" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 31, 9, 0), input: "53cm Körpergröße", facts: [ "Körpergröße 53 cm" ], parseable_data: [ { "type" => "height", "value" => 53, "unit" => "cm" } ])

    get person_root_url(person_slug: person.name, tab: "overview")

    assert_response :success
    assert_includes @response.body, "Weight trend"
    assert_select "#research_chat_form", 0
    assert_select "#overview_weight_activity", 1
    assert_select "#overview_baby_tracking_feeding", 0
    assert_select "#overview_baby_tracking_sleep", 0
    assert_select "#overview_baby_tracking_diaper", 0
    assert_select "#overview_baby_activity_feeding", 0
    assert_select "#overview_baby_activity_sleep", 0
    assert_select "#overview_baby_activity_diaper", 0
    assert_select "#overview_height_activity", 0
    assert_select "h2", text: /Protocol - Demo Mila/, count: 0
  end

  test "shows skipped parse entry in log" do
    person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), input: "Plain input", parseable_data: [], parse_status: "skipped")

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Plain input"
    assert_select "details[data-entry-collapsible='true']", 1
  end

  test "shows cockpit without baby badge by default" do
    person = Person.create!(name: "BabyUser", birth_date: Date.new(2024, 1, 1))

    get person_root_url(person_slug: person.name)

    assert_response :success
    assert_select "h2", text: /BabyUser/
    assert_select "span", text: I18n.t("baby.badge"), count: 0
  end

  test "cockpit renders activity badges with input facts and parseable data" do
    person = Person.create!(name: "Demo Theo", birth_date: Date.new(2024, 1, 1))
    entry = person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 31, 10, 0),
      input: "breastfed left side for 18 minutes",
      facts: [ "Breast feeding left 18 min" ],
      parseable_data: [ { "type" => "breast_feeding", "value" => 18, "unit" => "min", "side" => "left" } ]
    )

    get person_root_url(person_slug: person.name)

    assert_response :success
    assert_select "#chat_activity_entry_#{entry.id}", 1
    assert_not_includes @response.body, "Recent Activity"
    assert_includes @response.body, "Breast feeding left 18 min"
    assert_includes @response.body, "Input"
    assert_includes @response.body, "Parsed"
    assert_includes @response.body, I18n.t("entries.data_labels.breast_feeding")
  end

  test "recent activity summary clamps long text" do
    person = Person.create!(name: "Clampy", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 3, 31, 9, 0),
      input: "Bla" * 120,
      facts: [],
      parseable_data: []
    )

    get person_root_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "line-clamp-6"
    assert_not_includes @response.body, "line-clamp-2"
  end

  test "cockpit shows weight widget when weight data exists" do
    person = Person.create!(name: "Weighty", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: 3.days.ago, input: "75kg", facts: [ "Weight 75 kg" ], parseable_data: [ { "type" => "weight", "value" => 75, "unit" => "kg" } ])
    person.entries.create!(occurred_at: 1.day.ago, input: "74.2kg", facts: [ "Weight 74.2 kg" ], parseable_data: [ { "type" => "weight", "value" => 74.2, "unit" => "kg" } ])

    get person_root_url(person_slug: person.name, tab: "overview")

    assert_response :success
    assert_select "#overview_weight_activity", 1
    assert_includes @response.body, "Weight trend"
    assert_includes @response.body, "74.2 kg"
  end

  test "cockpit shows planning widget when appointment and goal task data exist" do
    person = Person.create!(name: "Planner", birth_date: Date.new(2024, 1, 1))
    scheduled_for = (Time.zone.today + 2.days).to_time.change(hour: 10, min: 30).iso8601
    person.entries.create!(occurred_at: Time.current, input: "doctor appointment", facts: [ "Doctor appointment" ], parseable_data: [ { "type" => "appointment", "value" => "doctor appointment", "scheduled_for" => scheduled_for, "location" => "hospital" } ])
    person.entries.create!(occurred_at: Time.current, input: "todo bring card", facts: [ "Bring vaccination card" ], parseable_data: [ { "type" => "todo", "value" => "bring vaccination card" } ])

    get person_root_url(person_slug: person.name, tab: "overview")

    assert_response :success
    assert_select "#overview_planning", 1
    assert_includes @response.body, "Appointments, goals &amp; tasks"
    assert_includes @response.body, "Appointment"
    assert_includes @response.body, "Goal/task"
  end

  test "planning widget shows five appointments and goals tasks before expanding" do
    person = Person.create!(name: "Scroll Planner", birth_date: Date.new(2024, 1, 1))

    6.times do |index|
      scheduled_for = (Time.zone.today + index.days + 1).to_time.change(hour: 10).iso8601
      person.entries.create!(occurred_at: Time.current + index.minutes, input: "appointment #{index}", facts: [ "Appointment #{index}" ], parseable_data: [ { "type" => "appointment", "value" => "appointment #{index}", "scheduled_for" => scheduled_for } ])
      person.entries.create!(occurred_at: Time.current + index.minutes, input: "todo #{index}", facts: [ "Todo #{index}" ], parseable_data: [ { "type" => "todo", "value" => "todo #{index}" } ])
    end

    get person_root_url(person_slug: person.name, tab: "overview")

    assert_response :success
    assert_select "#overview_planning details", 2
    assert_includes @response.body, I18n.t("person.overview.appointments.show_all", count: 6)
    assert_includes @response.body, "Show all 6 goals &amp; tasks"
    assert_includes @response.body, "Appointment 4"
    assert_includes @response.body, "Appointment 5"
    assert_includes @response.body, "todo 0"
  end

  test "cockpit activity badges prefer facts text" do
    person = Person.create!(name: "FactsFirst", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 4, 2, 10, 0),
      input: "doctor appointment",
      facts: [ "Doctor appointment with Dr. Meier" ],
      parseable_data: [ { "type" => "appointment", "value" => "checkup", "location" => "hospital" } ]
    )

    get person_root_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Doctor appointment with Dr. Meier"
  end

  test "cockpit shows pulse and blood pressure widgets" do
    person = Person.create!(name: "Vitals", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 10, 0), input: "37.8 temp", facts: [ "Temperature 37.8 C" ], parseable_data: [ { "type" => "temperature", "value" => 37.8, "unit" => "C" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 11, 0), input: "Pulse 120", facts: [ "Pulse 120 bpm" ], parseable_data: [ { "type" => "pulse", "value" => 120, "unit" => "bpm" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 2, 12, 0), input: "BP 120/80", facts: [ "Blood pressure 120/80 mmHg" ], parseable_data: [ { "type" => "blood_pressure", "systolic" => 120, "diastolic" => 80, "unit" => "mmHg" } ])

    get person_root_url(person_slug: person.name, tab: "overview")

    assert_response :success
    assert_select "#overview_temperature_activity", 0
    assert_select "#overview_pulse_activity", 1
    assert_select "#overview_blood_pressure_activity", 1
  end

  test "shows dedicated baby page when baby mode enabled" do
    person = Person.create!(name: "Demo Mila", birth_date: Date.new(2025, 1, 1), baby_mode: true)
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

  test "cockpit still shows planning widget when empty" do
    person = Person.create!(name: "EmptyWidgets", birth_date: Date.new(2024, 1, 1))

    get person_root_url(person_slug: person.name, tab: "overview")

    assert_response :success
    assert_select "#overview_planning", 1
    assert_includes @response.body, "No appointments yet."
    assert_includes @response.body, "No goals or tasks yet."
  end

  test "log can sort by entered time" do
    person = Person.create!(name: "Sorty", birth_date: Date.new(2024, 1, 1))
    older_entry = nil
    newer_entry = nil

    travel_to Time.zone.local(2026, 3, 31, 9, 0, 0) do
      older_entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 31, 8, 0, 0), input: "older input", facts: [ "Older fact" ], parseable_data: [])
    end

    travel_to Time.zone.local(2026, 3, 31, 10, 0, 0) do
      newer_entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 30, 8, 0, 0), input: "newer input", facts: [ "Newer fact" ], parseable_data: [])
    end

    get person_log_url(person_slug: person.name, sort: "entered")
    assert_response :success
    assert @response.body.index("Newer fact") < @response.body.index("Older fact")
  end

  test "files tab lists uploaded documents" do
    person = Person.create!(name: "Filesy", birth_date: Date.new(2024, 1, 1))
    entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "Doctor invoice", extracted_data: { "facts" => [ { "text" => "Doctor invoice uploaded", "kind" => "note", "value" => "Insurance invoice", "ref" => "INV-2026" } ], "document" => { "type" => "invoice", "title" => "Doctor invoice from March 2026", "total_amount" => 20.11, "currency" => "EUR" }, "llm" => {} }, parse_status: "parsed")
    entry.documents.attach(io: StringIO.new(fake_pdf_content("Doctor invoice")), filename: "doctor-invoice.pdf", content_type: "application/pdf")

    get person_files_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Files for Filesy"
    assert_includes @response.body, "doctor-invoice.pdf"
    assert_includes @response.body, "Doctor invoice from March 2026"
    assert_includes @response.body, "20,11 EUR"
    assert_includes @response.body, I18n.t("files.reparse.document_button")
    assert_includes @response.body, I18n.t("files.reparse.button")
  end

  test "files tab can queue all document entries for reparse" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Bulk Files", birth_date: Date.new(2024, 1, 1))
    other_person = Person.create!(name: "Other Files", birth_date: Date.new(2024, 1, 1))
    document_entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "Doctor invoice", extracted_data: { "facts" => [ { "text" => "Old document fact", "kind" => "note" } ], "document" => { "type" => "invoice" }, "llm" => {} }, parse_status: "parsed")
    document_entry.documents.attach(io: StringIO.new(fake_pdf_content("Doctor invoice")), filename: "doctor-invoice.pdf", content_type: "application/pdf")
    plain_entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 9, 0), input: "Plain note", extracted_data: { "facts" => [ { "text" => "Keep me", "kind" => "note" } ], "document" => {}, "llm" => {} }, parse_status: "parsed")
    other_document_entry = other_person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 10, 0), input: "Other invoice", extracted_data: { "facts" => [ { "text" => "Other fact", "kind" => "note" } ], "document" => { "type" => "invoice" }, "llm" => {} }, parse_status: "parsed")
    other_document_entry.documents.attach(io: StringIO.new(fake_pdf_content("Other invoice")), filename: "other-invoice.pdf", content_type: "application/pdf")

    assert_enqueued_with(job: EntryReparseBatchJob) do
      post person_files_reparse_url(person_slug: person.name)
    end

    assert_redirected_to person_files_path(person_slug: person.name)
    assert_equal "pending", document_entry.reload.parse_status
    assert_equal [], document_entry.fact_objects
    assert_equal "parsed", plain_entry.reload.parse_status
    assert_equal "parsed", other_document_entry.reload.parse_status
  end

  test "file detail page shows in-app viewer and parsed sidebar" do
    person = Person.create!(name: "File Detail", birth_date: Date.new(2024, 1, 1))
    entry = person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "Doctor invoice", extracted_data: { "facts" => [ { "text" => "Doctor invoice uploaded", "kind" => "note", "value" => "Insurance invoice", "ref" => "INV-2026" } ], "document" => { "type" => "invoice", "title" => "Doctor invoice from March 2026", "total_amount" => 20.11, "currency" => "EUR" }, "llm" => {} }, parse_status: "parsed")
    entry.documents.attach(io: StringIO.new(fake_pdf_content("Doctor invoice")), filename: "doctor-invoice.pdf", content_type: "application/pdf")

    get person_file_url(person_slug: person.name, entry_id: entry.id)

    assert_response :success
    assert_includes @response.body, "Parsed data"
    assert_includes @response.body, "Doctor invoice from March 2026"
    assert_includes @response.body, "Invoice total: 20,11 EUR"
    assert_includes @response.body, "Doctor invoice uploaded"
    assert_includes @response.body, "Type"
    assert_includes @response.body, "Note"
    assert_includes @response.body, "Insurance invoice"
    assert_includes @response.body, "Reference"
    assert_no_match(/>TEXT</, @response.body)
    assert_no_match(/>KIND</, @response.body)
    assert_no_match(/>VALUE</, @response.body)
    assert_includes @response.body, "Back to files"
    assert_includes @response.body, "iframe"
  end

  test "file content streams inline for selected document" do
    person = Person.create!(name: "File Content", birth_date: Date.new(2024, 1, 1))
    entry = person.entries.build(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "", extracted_data: { "facts" => [], "document" => {}, "llm" => {} }, parse_status: "parsed")
    entry.documents.attach(io: StringIO.new(fake_pdf_content("Doctor invoice")), filename: "doctor-invoice.pdf", content_type: "application/pdf")
    entry.save!

    get person_file_content_url(person_slug: person.name, entry_id: entry.id)

    assert_response :success
    assert_equal "application/pdf", @response.media_type
    assert_includes @response.headers["Content-Disposition"], "inline"
    assert_includes @response.headers["Content-Disposition"], "doctor-invoice.pdf"
  end

  test "files tab highlights failed documents and shows inline retry" do
    person = Person.create!(name: "Files Retry", birth_date: Date.new(2024, 1, 1))
    entry = person.entries.build(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "", extracted_data: { "facts" => [], "document" => {}, "llm" => {} }, parse_status: "failed")
    entry.documents.attach(io: StringIO.new(fake_pdf_content("Failed invoice")), filename: "failed-invoice.pdf", content_type: "application/pdf")
    entry.save!

    get person_files_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "failed-invoice.pdf"
    assert_includes @response.body, I18n.t("files.reparse.document_button")
    assert_includes @response.body, I18n.t("entries.tags.parse_error")
  end

  test "data healthkit tab shows summary entries and sync state" do
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

    get person_log_url(person_slug: person.name, tab: "healthkit")

    assert_response :success
    assert_select "nav[aria-label=?]", I18n.t("dashboard.data.tabs.label")
    assert_includes @response.body, "HealthKit for Healthkitty"
    assert_includes @response.body, "iphone-main"
    assert_includes @response.body, "Remove imported HealthKit data"
    assert_includes @response.body, "Regenerate summaries"
    assert_includes @response.body, "Reparse summaries"
  end

  test "data healthkit tab uses browser time zone cookie for displayed times" do
    person = Person.create!(name: "ZoneKit", birth_date: Date.new(2024, 1, 1))
    person.healthkit_syncs.create!(
      device_id: "iphone-main",
      status: "synced",
      last_synced_at: Time.utc(2026, 4, 6, 7, 30),
      last_successful_sync_at: Time.utc(2026, 4, 6, 7, 30),
      synced_record_count: 42
    )

    cookies[:browser_time_zone] = "Europe/Berlin"

    get person_log_url(person_slug: person.name, tab: "healthkit")

    assert_response :success
    assert_includes @response.body, "09:30"
  end

  test "data healthkit tab shows stats and links to log" do
    person = Person.create!(name: "PagedKit", birth_date: Date.new(2024, 1, 1))

    3.times do |index|
      person.entries.create!(
        source: Entry::SOURCES[:healthkit],
        source_ref: "healthkit:day:2026-03-#{format('%02d', index + 1)}",
        occurred_at: Time.zone.local(2026, 3, index + 1, 23, 59),
        input: "Apple Health daily summary for March #{index + 1}, 2026.",
        facts: [],
        parseable_data: [],
        parse_status: "parsed"
      )
    end

    get person_log_url(person_slug: person.name, tab: "healthkit")

    assert_response :success
    assert_includes @response.body, "3"
    assert_select "a[href*='source=healthkit']"
    assert_select "turbo-frame#healthkit_records_table_frame[src*='healthkit/records?page=1']"
  end

  test "data record tab shows the full llm patient record context" do
    person = Person.create!(name: "Record Rita", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 4, 8, 9, 0),
      input: "Ibuprofen 10 mg",
      facts: [ "Ibuprofen 10 mg" ],
      parseable_data: [ { "type" => "medication", "value" => "Ibuprofen", "dose" => "10 mg" } ],
      parse_status: "parsed"
    )

    get person_log_url(person_slug: person.name, tab: "record")

    assert_response :success
    assert_select "nav[aria-label=?]", I18n.t("dashboard.data.tabs.label")
    assert_select "#patient_record_panel", 1
    assert_includes @response.body, I18n.t("dashboard.data.tabs.record")
    assert_includes @response.body, "# Patientenakte: Record Rita"
    assert_includes @response.body, "Ibuprofen 10 mg"
    assert_includes @response.body, "Freshness rules"
    assert_includes @response.body, "Cockpit rules"
  end

  test "healthkit records page loads first 250 rows lazily" do
    person = Person.create!(name: "HeavyKit", birth_date: Date.new(2024, 1, 1))

    260.times do |index|
      person.healthkit_records.create!(
        device_id: "iphone-main",
        external_id: "record-#{index}",
        record_type: "HKQuantityTypeIdentifierStepCount",
        source_name: "Health",
        start_at: Time.zone.local(2026, 4, 5, 8, 0) - index.minutes,
        payload: { "quantity" => "#{index} count" }
      )
    end

    get person_healthkit_records_url(person_slug: person.name)

    assert_response :success
    assert_select "turbo-frame#healthkit_records_table_frame"
    assert_select "tbody#db_table_rows tr", 250
    assert_includes @response.body, "250 loaded"
    assert_select "turbo-frame#db_table_pagination[src*='page=2']"
  end

  test "healthkit page can queue summary rebuild" do
    person = Person.create!(name: "Queue Sync", birth_date: Date.new(2024, 1, 1))

    assert_enqueued_with(job: HealthkitSummarySyncJob, args: [ person.id ]) do
      post person_healthkit_sync_summaries_url(person_slug: person.name)
    end

    assert_redirected_to person_log_path(person_slug: person.name, tab: "healthkit")
  end

  test "healthkit page can queue reparse" do
    person = Person.create!(name: "Queue Reparse", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    entry = person.entries.create!(
      source: Entry::SOURCES[:healthkit],
      source_ref: "healthkit:day:2026-03-01",
      occurred_at: Time.zone.local(2026, 3, 1, 23, 59),
      input: "Apple Health daily summary for March 1, 2026.",
      extracted_data: { "facts" => [ { "text" => "Old summary", "kind" => "summary" } ], "document" => {}, "llm" => { "status" => "structured" } },
      parse_status: "parsed"
    )

    assert_enqueued_with(job: EntryReparseBatchJob) do
      post person_healthkit_reparse_url(person_slug: person.name)
    end

    assert_redirected_to person_log_path(person_slug: person.name, tab: "healthkit")
    assert_equal "pending", entry.reload.parse_status
    assert_equal [], entry.fact_objects
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
    person = Person.create!(name: "Demo Mila", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 12, 0), input: "Stillen links 12 min; Windel: nass + fest", facts: [ "Stillen links 12 min", "Windel nass und fest" ], parseable_data: [ { "type" => "breast_feeding", "value" => 12, "unit" => "min", "side" => "left" }, { "type" => "diaper", "wet" => true, "solid" => true } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 19, 30), input: "Windel: nass + fest", facts: [ "Windel nass und fest" ], parseable_data: [ { "type" => "diaper", "wet" => true, "solid" => true } ])

    get person_log_url(person_slug: person.name, date: "2026-03-29", parseable_type: "breast_feeding")

    assert_response :success
    assert_includes @response.body, "breast_feeding · Breastfeeding"
    assert_includes @response.body, "Stillen links 12 min"
    assert_not_includes @response.body, "March 29, 2026 19:30"
  end

  test "log page merges filters and entries without the manual composer" do
    person = Person.create!(name: "Flat Data", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 8, 0), input: "Ibuprofen 10 mg", facts: [ "Ibuprofen 10 mg" ], parseable_data: [])

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_select "#overview_composer", 0
    assert_select "section#log_entries", 1
    assert_select "section#log_entries #log_header form", 1
    assert_select "section#log_entries #log_header select[name='sort']", 1
    assert_select "section#log_entries #log_header span", text: I18n.t("baby.badge"), count: 0
    assert_select "section#log_entries details[data-entry-collapsible='true']", 1
  end
end
