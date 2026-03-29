class EntriesController < ApplicationController
  before_action :set_person
  before_action :set_entry, only: [ :destroy ]

  def create
    @entry = @person.entries.build(entry_params)
    if @entry.has_attribute?(:parse_status)
      @entry.parse_status = @entry.data.blank? ? "pending" : "parsed"
    end

    if @entry.save
      EntryDataParseJob.perform_later(@entry.id) if @entry.data.blank?

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

  private

  def set_person
    @person = Person.find(params[:person_id])
  end

  def set_entry
    @entry = @person.entries.find(params[:id])
  end

  def entry_params
    permitted = params.require(:entry).permit(:note, :occurred_at)
    permitted[:data] = normalize_data_param(params[:entry][:data]) if params[:entry].key?(:data)
    permitted
  end

  def normalize_data_param(raw_data)
    return [] if raw_data.blank?
    return raw_data if raw_data.is_a?(Array)

    JSON.parse(raw_data)
  rescue JSON::ParserError
    []
  end
end
