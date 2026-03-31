require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "shows the log tab by default" do
    Person.delete_all
    get root_url

    assert_response :success
    assert_select "button", text: /Family/
    assert_select "a[aria-label='Settings']", 1
  end

  test "shows family member name when people exist" do
    get root_url

    assert_response :success
    # When fixtures are loaded, should show the first person's name
    assert_select "button", text: /MyString/
  end

  test "sets locale from user preferences" do
    UserPreference.update_locale("de")

    get root_url

    assert_response :success
    assert_select "a[aria-label='Einstellungen']", 1

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
    assert_includes @response.body, I18n.l(person.entries.first.display_time, format: :long)
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

  test "shows compact baby widgets on overview instead of full log layout" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_select "h2", /Baby quick actions|Baby-Schnellaktionen/, 1
    assert_includes @response.body, "Breast"
    assert_includes @response.body, "Bottle"
    assert_select "h2", text: /Protocol - Marlon/, count: 0
  end

  test "shows llm not configured state for skipped parsing" do
    person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), input: "Plain input", parseable_data: [], parse_status: "skipped")

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "LLM parsing is off until a model is configured in Settings."
  end

  test "shows baby mode toggle on person overview" do
    person = Person.create!(name: "BabyUser", birth_date: Date.new(2024, 1, 1))

    get person_overview_url(person_slug: person.name)

    assert_response :success
    assert_select "a[aria-label='Edit person']", 1
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
end
