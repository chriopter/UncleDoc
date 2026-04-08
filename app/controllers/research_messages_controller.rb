class ResearchMessagesController < ApplicationController
  before_action :set_person

  def create
    @chat = @person.chat || @person.build_chat
    @message = Message.new
    @error_message = nil
    @new_visible_messages = []
    content = params.dig(:message, :content).presence || params.dig(:llm_message, :content).presence
    content = content.to_s.strip

    if content.blank?
      render_form_error(nil) and return
    end

    configuration_error = ResearchChatRuntime.configuration_error_for(app_setting)
    if configuration_error
      render_form_error(t("log_summary.states.#{configuration_error}")) and return
    end

    ResearchChatRuntime.prepare!(@chat, setting: app_setting)
    first_visible_message = @chat.visible_messages.none?
    latest_visible_id = @chat.visible_messages.maximum(:id) || 0
    @chat.add_message(role: :user, content: content)

    ResearchChatResponseJob.perform_later(@chat.id, I18n.locale.to_s)

    @new_visible_messages = @chat.visible_messages.where("id > ?", latest_visible_id)

    render turbo_stream: success_streams(first_visible_message)
  end

  private

  def set_person
    @person = Person.find_by!(name: params[:person_slug])
  end

  def render_form_error(message)
    @chat = @person.chat
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
        locals: { person: @person, message: Message.new, error_message: nil }
      )
    ]
    @new_visible_messages.each do |message|
      streams << turbo_stream.append("chat_messages", partial: message.to_partial_path, locals: { message: message })
    end
    streams << turbo_stream.remove("chat_welcome") if first_visible_message
    streams
  end
end
