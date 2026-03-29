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
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), note: "Mild fever in the evening", data: [])

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_match(/Alice/, @response.body)
    assert_includes @response.body, "Protocol - Alice"
    assert_includes @response.body, "Mild fever in the evening"
  end

  test "shows baby dashboard and ai summary on baby log page" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 9, 0), note: "Bottle 120ml", data: [ { "type" => "bottle_feeding", "value" => 120, "unit" => "ml" } ])
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 29, 10, 0), note: "Peter has fever 39.2", data: [], parse_status: "pending")

    get person_log_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "Log for Marlon"
    assert_includes @response.body, "Show raw data"
    assert_includes @response.body, "Sending note to the LLM"
  end

  test "shows compact baby widgets on overview instead of full log layout" do
    person = Person.create!(name: "Marlon", birth_date: Date.new(2025, 1, 1), baby_mode: true)

    get root_url

    assert_response :success
    assert_select "h2", /Baby quick actions|Baby-Schnellaktionen/, 1
    assert_select "h2", text: /Protocol - Marlon/, count: 0
  end

  test "shows llm not configured state for skipped parsing" do
    person = Person.create!(name: "Alice", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), note: "Plain note", data: [], parse_status: "skipped")

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
    person.entries.create!(occurred_at: Time.zone.local(2026, 3, 28, 20, 0), note: "Plain note", data: [], parse_status: "pending")

    get root_url(person_slug: person.name)

    assert_response :success
    assert_includes @response.body, "1 entry parsing"
  end
end
