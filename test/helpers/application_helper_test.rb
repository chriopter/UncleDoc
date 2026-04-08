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
end
