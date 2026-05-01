class RecordHealthEntryTool < RubyLLM::Tool
  description "Create UncleDoc health entries from the current user message and its attached documents. Use this when the user provides new health data, asks to save/log something, or uploads documents. Create one document entry per attached file."

  param :reason, desc: "Short reason for creating the health entry", required: false

  def initialize(person:, message:)
    @person = person
    @message = message
  end

  def execute(reason: nil)
    return { status: "skipped", error: "No user message is available." } unless @message
    return { status: "skipped", error: "The entry parser is not configured." } unless EntryDataParser.ready?

    entries = find_or_create_entries
    entries.each do |entry|
      EntryDataParseJob.perform_now(entry.id) if entry.pending_parse?
      entry.reload
    end

    {
      status: combined_status(entries),
      entry_ids: entries.map(&:id),
      entries: entries.map { |entry| entry_payload(entry) },
      reason: reason.to_s.presence
    }.compact
  rescue ActiveRecord::RecordInvalid => error
    { status: "failed", error: error.record.errors.full_messages.to_sentence }
  end

  private

  def find_or_create_entries
    return [ find_or_create_text_entry ] unless @message.attachments.attached?

    attachments = @message.attachments.attachments.includes(:blob).to_a
    if attachments.one? && (legacy_entry = find_legacy_message_entry)
      return [ legacy_entry ]
    end

    attachments.each_with_index.map do |attachment, index|
      find_or_create_document_entry(attachment, index:)
    end
  end

  def find_or_create_text_entry
    find_or_create_entry(source_ref: "chat:message:#{@message.id}", input: @message.content.to_s)
  end

  def find_or_create_document_entry(attachment, index:)
    source_ref = "chat:message:#{@message.id}:attachment:#{attachment.blob_id}"
    input = index.zero? ? @message.content.to_s : ""

    find_or_create_entry(source_ref:, input:) do |entry|
      entry.documents.attach(attachment.blob)
    end
  end

  def find_or_create_entry(source_ref:, input:)
    existing_entry = @person.entries.find_by(source: Entry::SOURCES[:manual], source_ref:)
    return existing_entry if existing_entry

    entry = @person.entries.build(input:, occurred_at: Time.current, parse_status: "pending", source_ref:)
    yield entry if block_given?
    entry.save!
    DocumentThumbnailWarmJob.perform_later(entry.id) if entry.documents_attached?
    entry
  end

  def find_legacy_message_entry
    @person.entries.find_by(source: Entry::SOURCES[:manual], source_ref: "chat:message:#{@message.id}")
  end

  def entry_payload(entry)
    {
      status: entry.parse_status,
      entry_id: entry.id,
      title: entry.document_title.presence || entry.fact_summary.presence || entry.input.presence || I18n.t("entries.documents.document_only"),
      document_types: entry.document_types,
      documents: entry.document_names,
      facts: entry.fact_items,
      invoice_total: entry.invoice_total_label
    }.compact
  end

  def combined_status(entries)
    statuses = entries.map(&:parse_status)
    return "failed" if statuses.include?("failed")
    return "pending" if statuses.include?("pending")
    return "skipped" if statuses.include?("skipped")

    "parsed"
  end
end
