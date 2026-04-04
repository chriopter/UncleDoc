class DashboardController < ApplicationController
  def show
    @person = Person.new
    @people = Person.recent_first

    if current_person
      @entry = Entry.new
      @entry_sort = entry_sort_mode(params)
      @entries = current_person.entries.merge(Entry.sorted_by(@entry_sort))
    end
  end

  def log
    @person = Person.find_by!(name: params[:person_slug])
    @entry = Entry.new
    @entry_sort = entry_sort_mode(params)
    @available_log_filters = available_log_filters(@person)
    @entries = filtered_entries(@person, @entry_sort)
    @log_summary_state = :idle
  end

  def files
    @person = Person.find_by!(name: params[:person_slug])
    @document_entries = @person.entries.with_documents.recent_first
    @document_count = @document_entries.sum(&:document_count)
  end

  def summarize_log
    @person = Person.find_by!(name: params[:person_slug])
    @entry = Entry.new
    @entry_sort = entry_sort_mode(params)
    @available_log_filters = available_log_filters(@person)
    @entries = filtered_entries(@person, @entry_sort)

    result = LogSummaryGenerator.call(person: @person, entries: @entries, preference: user_preference)
    @log_summary = result.summary
    @log_summary_state = result.error || :ready

    render turbo_stream: turbo_stream.replace(
      "log_summary_output",
      partial: "dashboard/log_summary_inline",
      locals: { summary: @log_summary, state: @log_summary_state }
    )
  end

  private

  def entry_sort_mode(params_hash)
    params_hash[:sort].to_s == "entered" ? "entered" : "occurred"
  end

  def filtered_entries(person, sort_mode)
    scope = person.entries.merge(Entry.sorted_by(sort_mode))

    if params[:date].present?
      date = Date.iso8601(params[:date]) rescue nil
      scope = scope.where(occurred_at: date.all_day) if date
    end

    if params[:parseable_type].present?
      scope = scope.by_parseable_data_type(params[:parseable_type])
    end

    scope
  end

  def available_log_filters(person)
    dates = person.entries.order(occurred_at: :desc).pluck(:occurred_at).compact.map(&:to_date).uniq
    types = person.entries.flat_map { |entry| Array(entry.parseable_data).filter_map { |item| item.is_a?(Hash) ? item["type"].presence : nil } }.uniq.sort

    filter_options = types.map { |type| [ "#{type} · #{I18n.t("entries.data_labels.#{type}", default: type.humanize)}", type ] }

    { dates: dates, parseable_type_options: filter_options }
  end
end
