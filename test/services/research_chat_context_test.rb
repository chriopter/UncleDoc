require "test_helper"

class ResearchChatContextTest < ActiveSupport::TestCase
  test "system prompt includes latest structured record and freshness rules" do
    person = Person.create!(name: "Prompt Pia", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 4, 8, 9, 15),
      input: "Fever 38.2 after lunch",
      facts: [ "Temperature 38.2 C" ],
      parseable_data: [ { "type" => "temperature", "value" => 38.2, "unit" => "C" } ]
    )

    prompt = travel_to(Time.zone.local(2026, 5, 1, 12, 0)) do
      ResearchChatContext.system_prompt_for(person)
    end

    assert_includes prompt, "Patientenakte: Prompt Pia"
    assert_includes prompt, "Temperature 38.2 C"
    assert_includes prompt, "value: 38.2"
    assert_includes prompt, "Health timeline"
    assert_includes prompt, "Freshness rules:"
    assert_includes prompt, "prefer the current patient record"
  end

  test "system prompt exposes appointments and open goals as patient record context" do
    person = Person.create!(name: "Planning Pia", birth_date: Date.new(2024, 1, 1))
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 5, 1, 9, 0),
      input: "Doctor appointment tomorrow",
      facts: [ "Doctor appointment tomorrow" ],
      parseable_data: [ { "type" => "appointment", "value" => "doctor appointment", "scheduled_for" => "2026-05-02T10:30:00Z", "location" => "practice" } ]
    )
    person.entries.create!(
      occurred_at: Time.zone.local(2026, 5, 1, 10, 0),
      input: "I want to lose 20 kg",
      facts: [ "Goal: lose 20 kg" ],
      parseable_data: [ { "type" => "todo", "value" => "lose 20 kg", "quality" => "goal" } ],
      todo_done: false
    )

    prompt = travel_to(Time.zone.local(2026, 5, 1, 12, 0)) do
      ResearchChatContext.system_prompt_for(person)
    end

    assert_includes prompt, "Upcoming appointments"
    assert_includes prompt, "doctor appointment"
    assert_includes prompt, "location: practice"
    assert_includes prompt, "Open goals & tasks"
    assert_includes prompt, "lose 20 kg"
    assert_includes prompt, "quality: goal"
    assert_includes prompt, "Appointments, open goals, and open tasks are part of the patient record"
    assert_includes prompt, "supports or conflicts with an open goal"
  end

  test "refresh_needed tracks entry updates and missing context" do
    person = Person.create!(name: "Refresh Ria", birth_date: Date.new(2024, 1, 1))
    chat = person.build_chat
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)

    assert ResearchChatContext.refresh_needed?(chat)

    ResearchChatContext.refresh!(chat, locale: :en)
    assert_not ResearchChatContext.refresh_needed?(chat)

    travel 1.minute do
      person.entries.create!(occurred_at: Time.zone.local(2026, 4, 8, 10, 0), input: "New note", facts: [ "New fact" ], parseable_data: [])
    end

    assert ResearchChatContext.refresh_needed?(chat)
  end
end
