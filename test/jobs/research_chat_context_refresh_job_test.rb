require "test_helper"

class ResearchChatContextRefreshJobTest < ActiveJob::TestCase
  test "job refreshes chat context and adds the notice without an llm request" do
    person = Person.create!(name: "Refresh Rina", birth_date: Date.new(2024, 1, 1))
    AppSetting.current.update!(llm_provider: "ollama", llm_model: "llama3")
    person.entries.create!(occurred_at: Time.zone.local(2026, 4, 8, 9, 0), input: "No fever", facts: [ "No fever" ], parseable_data: [])

    chat = ResearchChatRuntime.prepare!(person.build_chat, setting: AppSetting.current)
    ResearchChatContext.refresh!(chat, locale: :en)

    travel 1.minute do
      person.entries.create!(occurred_at: Time.zone.local(2026, 4, 8, 10, 0), input: "Fever 38.4", facts: [ "Fever 38.4 C" ], parseable_data: [ { "type" => "temperature", "value" => 38.4, "unit" => "C" } ])
    end

    assert_difference -> { chat.reload.messages.visible.where(message_kind: "context_notice").count }, 1 do
      ResearchChatContextRefreshJob.perform_now(person.id, "en")
    end

    assert_includes chat.reload.context_message.content, "Fever 38.4 C"
    assert_equal I18n.t("chat.context_refreshed", locale: :en), chat.messages.visible.where(message_kind: "context_notice").last&.content
  end
end
