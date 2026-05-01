require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "render_chat_markdown keeps headings and following lists" do
    text = <<~TEXT
      **Kurz gesagt:** **nicht alarmierend kaputt, aber klar verbesserungsbeduerftig.**

      ### Was die Akte insgesamt zeigt
      - Du warst ueber lange Strecken **ziemlich aktiv**.
      - Seit etwa **2024 bis 2026** ist die **Bewegung deutlich niedriger**.

      ### Mein Eindruck
      Du wirkst in den Daten **nicht schwer krank**.
    TEXT

    html = render_chat_markdown(text)

    assert_includes html, "<strong"
    assert_includes html, "Was die Akte insgesamt zeigt"
    assert_includes html, "<ul"
    assert_includes html, "Du warst ueber lange Strecken"
    assert_includes html, "Mein Eindruck"
    assert_includes html, "nicht schwer krank"
  end

  test "chat timeline anchors chat-created document entries after the upload message" do
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    person = Person.create!(name: "Upload Uma", birth_date: Date.new(2024, 1, 1))
    chat = person.build_chat
    ResearchChatRuntime.prepare!(chat, setting: AppSetting.current)

    travel_to Time.zone.local(2026, 4, 30, 13, 12, 0) do
      user_message = chat.add_message(role: :user, content: "1 Dokument angehängt")
      person.entries.create!(
        occurred_at: Time.zone.local(2025, 12, 30, 9, 0, 0),
        input: "Schiene",
        facts: [ "Retentionsschiene Rechnung" ],
        parseable_data: [],
        source_ref: "chat:message:#{user_message.id}",
        parse_status: "parsed"
      )
      chat.add_message(role: :assistant, content: "Gespeichert und aus dem Dokument geparst.")
    end

    timeline = chat_timeline_items(person, chat)

    assert_equal [ :message, :activity, :message ], timeline.map { |item| item[:kind] }
    assert_equal "1 Dokument angehängt", timeline.first[:record].content
    assert_equal "Schiene", timeline.second[:record].input
    assert_equal "Gespeichert und aus dem Dokument geparst.", timeline.third[:record].content
  end
end
