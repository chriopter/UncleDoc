class EntriesController < ApplicationController
  before_action :set_person
  before_action :set_entry, only: [ :show, :edit, :update, :destroy, :reparse, :toggle_todo ]

  def show
    return redirect_to person_log_path(person_slug: @person.name) unless turbo_frame_request?

    render partial: "entries/entry", locals: { entry: @entry }
  end

  def edit
    return redirect_to person_log_path(person_slug: @person.name) unless turbo_frame_request?

    render partial: "entries/edit_form", locals: { entry: @entry }
  end

  def create
    created_entries = build_create_entries
    @entry = created_entries.first || @person.entries.build(model_entry_params)

    if save_created_entries(created_entries)
      enqueue_parse_jobs(created_entries)

      respond_to do |format|
        format.html { redirect_to root_path(person_slug: @person.name, tab: "log"), notice: t("entries.flash.created") }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html do
          @tab = "log"
          @entries = @person.entries.recent_first
          render "dashboard/show", status: :unprocessable_entity
        end

        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "entry_form",
            partial: "entries/form",
            locals: { entry: @entry, person: @person }
          ), status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    @entry.destroy
    @entries = @person.entries.recent_first

    respond_to do |format|
      format.html { redirect_to root_path(person_slug: @person.name, tab: "log"), notice: t("entries.flash.destroyed") }
      format.turbo_stream
    end
  end

  def toggle_todo
    return redirect_back fallback_location: person_overview_path(person_slug: @person.name) unless @entry.todo?

    @entry.update!(todo_done: !@entry.todo_done?, todo_done_at: @entry.todo_done? ? nil : Time.current)

    respond_to do |format|
      format.html { redirect_back fallback_location: person_overview_path(person_slug: @person.name) }
      format.turbo_stream { redirect_back fallback_location: person_overview_path(person_slug: @person.name) }
    end
  end

  def reparse
    return redirect_back fallback_location: person_log_path(person_slug: @person.name) if @entry.babywidget_generated?

    force_reparse(@entry)
    @entry.save!

    EntryDataParseJob.perform_later(@entry.id) if @entry.pending_parse?

    respond_to do |format|
      format.html { redirect_back fallback_location: person_log_path(person_slug: @person.name), notice: t("entries.flash.reparse_requested") }
      format.turbo_stream { redirect_back fallback_location: person_log_path(person_slug: @person.name), notice: t("entries.flash.reparse_requested") }
    end
  end

  def update
    @entry.assign_attributes(entry_params)
    assign_document_source_ref(@entry) if uploaded_documents_present?
    should_enqueue_parse = prepare_reparse(@entry, documents_added: uploaded_documents_present?)

    if @entry.save
      EntryDataParseJob.perform_later(@entry.id) if should_enqueue_parse
      @entries = @person.entries.recent_first

      respond_to do |format|
        format.html { redirect_to person_log_path(person_slug: @person.name), notice: t("entries.flash.updated") }
        format.turbo_stream
      end
    else
      if turbo_frame_request?
        render partial: "entries/edit_form", locals: { entry: @entry }, status: :unprocessable_entity
      else
        redirect_to person_log_path(person_slug: @person.name), alert: @entry.errors.full_messages.to_sentence
      end
    end
  end

  private

  def set_person
    @person = Person.find(params[:person_id])
  end

  def set_entry
    @entry = @person.entries.find(params[:id])
  end

  def entry_params
    permitted = params.require(:entry).permit(:input, :occurred_at, :llm_response, facts: [], documents: [])
    permitted[:parseable_data] = normalize_parseable_data_param(params[:entry][:parseable_data]) if params[:entry].key?(:parseable_data)
    permitted[:facts] = normalize_facts_param(params[:entry][:facts]) if params[:entry].key?(:facts)
    permitted[:llm_response] = normalize_llm_response_param(params[:entry][:llm_response]) if params[:entry].key?(:llm_response)
    permitted
  end

  def model_entry_params
    entry_params.except(:documents)
  end

  def normalize_parseable_data_param(raw_parseable_data)
    return [] if raw_parseable_data.blank?
    return raw_parseable_data if raw_parseable_data.is_a?(Array)

    JSON.parse(raw_parseable_data)
  rescue JSON::ParserError
    []
  end

  def normalize_facts_param(raw_facts)
    return [] if raw_facts.blank?
    return raw_facts if raw_facts.is_a?(Array)

    JSON.parse(raw_facts)
  rescue JSON::ParserError
    []
  end

  def normalize_llm_response_param(raw_llm_response)
    return {} if raw_llm_response.blank?
    return raw_llm_response if raw_llm_response.is_a?(Hash)

    JSON.parse(raw_llm_response)
  rescue JSON::ParserError
    {}
  end

  def prepare_reparse(entry, documents_added: false)
    return false unless entry.will_save_change_to_input? || documents_added

    force_reparse(entry)
  end

  def force_reparse(entry)
    entry.extracted_data = { "facts" => [], "document" => {}, "llm" => {} }
    entry.todo_done = false if entry.has_attribute?(:todo_done)
    entry.todo_done_at = nil if entry.has_attribute?(:todo_done_at)

    if EntryDataParser.ready?
      entry.parse_status = "pending"
      true
    else
      entry.parse_status = "skipped"
      false
    end
  end

  def uploaded_documents_present?
    uploaded_document_files.any?
  end

  def build_create_entries
    return [ build_entry_for_documents ] if uploaded_document_files.size <= 1

    uploaded_document_files.each_with_index.map do |document, index|
      build_entry_for_documents(document:, input: index.zero? ? model_entry_params[:input] : "")
    end
  end

  def build_entry_for_documents(document: nil, input: model_entry_params[:input])
    entry = @person.entries.build(model_entry_params)
    entry.input = input

    if document
      attach_uploaded_document(entry, document)
      assign_document_source_ref(entry, document)
    else
      attach_uploaded_documents(entry)
      assign_document_source_ref(entry) if uploaded_documents_present?
    end

    should_enqueue_parse = entry.fact_objects.blank? && entry_has_parseable_source?(entry, documents_added: document.present? || uploaded_documents_present?) && EntryDataParser.ready? && !entry.babywidget_generated?

    entry.parse_status = if entry.fact_objects.present?
      "parsed"
    elsif should_enqueue_parse
      "pending"
    else
      "skipped"
    end

    entry
  end

  def save_created_entries(entries)
    Entry.transaction do
      entries.each(&:save!)
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def enqueue_parse_jobs(entries)
    entries.each do |entry|
      EntryDataParseJob.perform_later(entry.id) if entry.pending_parse?
    end
  end

  def uploaded_document_files
    Array(params.dig(:entry, :documents)).select do |document|
      document.respond_to?(:original_filename) && document.original_filename.present?
    end
  end

  def attach_uploaded_documents(entry)
    uploaded_document_files.each do |document|
      attach_uploaded_document(entry, document)
    end
  end

  def attach_uploaded_document(entry, document)
    document.tempfile.rewind
    entry.documents.attach(
      io: document.tempfile,
      filename: document.original_filename,
      content_type: document.content_type
    )
  end

  def entry_has_parseable_source?(entry, documents_added: false)
    entry.input.to_s.strip.present? || entry.documents_attached? || documents_added
  end

  def assign_document_source_ref(entry, document = uploaded_document_files.first)
    return if entry.source_ref.present?

    primary_name = document&.original_filename.to_s.parameterize.presence || "document"
    entry.source_ref = "upload:#{primary_name}:#{SecureRandom.hex(6)}"
  end
end
