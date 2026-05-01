class ResearchMessagesController < ApplicationController
  before_action :set_person

  def create
    @chat = @person.chat || @person.build_chat
    @message = Message.new
    @error_message = nil
    content = params.dig(:message, :content).presence || params.dig(:llm_message, :content).presence
    content = content.to_s.strip
    attachments = uploaded_message_files

    if content.blank? && attachments.empty?
      render_form_error(nil) and return
    end

    configuration_error = ResearchChatRuntime.configuration_error_for(app_setting)
    if configuration_error
      render_form_error(t("log_summary.states.#{configuration_error}")) and return
    end

    ResearchChatRuntime.prepare!(@chat, setting: app_setting)
    @user_message = @chat.add_message(role: :user, content: content.presence || t("chat.attachment_only_message", count: attachments.size))
    attach_message_files(@user_message, attachments)
    @assistant_message = @chat.messages.build(role: :assistant, content: "", message_kind: "streaming")
    @assistant_message.suppress_broadcast = true
    @assistant_message.save!

    ResearchChatResponseJob.perform_later(@chat.id, @assistant_message.id, I18n.locale.to_s)

    render turbo_stream: success_streams
  end

  private

  def set_person
    @person = Person.find_by!(name: params[:person_slug])
  end

  def uploaded_message_files
    Array(params.dig(:message, :attachments)).select do |attachment|
      attachment.respond_to?(:original_filename) && attachment.original_filename.present?
    end
  end

  def attach_message_files(message, attachments)
    attachments.each do |attachment|
      attachment.tempfile.rewind
      message.attachments.attach(
        io: attachment.tempfile,
        filename: attachment.original_filename,
        content_type: attachment.content_type
      )
    end
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

  def success_streams
    streams = [
      turbo_stream.replace(
        "research_chat_form",
        partial: "dashboard/chat_form",
        locals: { person: @person, message: Message.new, error_message: nil }
      )
    ]
    streams << turbo_stream.replace("chat_timeline", partial: "dashboard/chat_timeline", locals: { person: @person, chat: @chat })
    streams
  end
end
