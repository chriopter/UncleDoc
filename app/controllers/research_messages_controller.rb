class ResearchMessagesController < ApplicationController
  before_action :set_person

  def create
    @chat = @person.llm_chat || @person.build_llm_chat
    @message = LlmMessage.new
    @error_message = nil
    content = params.dig(:message, :content).to_s.strip

    if content.blank?
      render_form_error(nil) and return
    end

    configuration_error = ResearchChatRuntime.configuration_error_for(app_setting)
    if configuration_error
      render_form_error(t("log_summary.states.#{configuration_error}")) and return
    end

    ResearchChatRuntime.prepare!(@chat, setting: app_setting)
    first_visible_message = @chat.visible_messages.none?
    @chat.add_message(role: :user, content: content)
    ResearchChatResponseJob.perform_later(@chat.id, I18n.locale.to_s)

    render turbo_stream: success_streams(first_visible_message)
  end

  private

  def set_person
    @person = Person.find_by!(name: params[:person_slug])
  end

  def render_form_error(message)
    @chat = @person.llm_chat
    @error_message = message
    render turbo_stream: turbo_stream.replace(
      "research_chat_form",
      partial: "dashboard/chat_form",
      locals: { person: @person, message: @message, error_message: @error_message }
    ), status: :unprocessable_entity
  end

  def success_streams(first_visible_message)
    streams = [
      turbo_stream.replace(
        "research_chat_form",
        partial: "dashboard/chat_form",
      locals: { person: @person, message: LlmMessage.new, error_message: nil }
      )
    ]
    streams << turbo_stream.remove("chat_welcome") if first_visible_message
    streams
  end
end
