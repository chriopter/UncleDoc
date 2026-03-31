class EntriesController < ApplicationController
  before_action :set_person
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def show
    return redirect_to person_log_path(person_slug: @person.name) unless turbo_frame_request?

    render partial: "entries/entry", locals: { entry: @entry }
  end

  def edit
    return redirect_to person_log_path(person_slug: @person.name) unless turbo_frame_request?

    render partial: "entries/edit_form", locals: { entry: @entry }
  end

  def create
    @entry = @person.entries.build(entry_params)
    populate_facts_from_parseable_data(@entry)
    should_enqueue_parse = @entry.parseable_data.blank? && EntryDataParser.ready?

    if @entry.has_attribute?(:parse_status)
      @entry.parse_status = if @entry.parseable_data.present?
        "parsed"
      elsif should_enqueue_parse
        "pending"
      else
        "skipped"
      end
    end

    if @entry.save
      EntryDataParseJob.perform_later(@entry.id) if should_enqueue_parse

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

  def update
    @entry.assign_attributes(entry_params)
    populate_facts_from_parseable_data(@entry)
    should_enqueue_parse = prepare_reparse(@entry)

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
    permitted = params.require(:entry).permit(:input, :occurred_at, facts: [])
    permitted[:parseable_data] = normalize_parseable_data_param(params[:entry][:parseable_data]) if params[:entry].key?(:parseable_data)
    permitted[:facts] = normalize_facts_param(params[:entry][:facts]) if params[:entry].key?(:facts)
    permitted
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

  def prepare_reparse(entry)
    return false unless entry.will_save_change_to_input?

    entry.facts = [] if entry.has_attribute?(:facts)
    entry.parseable_data = []
    return false unless entry.has_attribute?(:parse_status)

    if EntryDataParser.ready?
      entry.parse_status = "pending"
      true
    else
      entry.parse_status = "skipped"
      false
    end
  end

  def populate_facts_from_parseable_data(entry)
    return unless entry.has_attribute?(:facts)
    return if entry.facts.present? || entry.parseable_data.blank?

    entry.facts = EntryFactListBuilder.call(entry.parseable_data)
  end
end
