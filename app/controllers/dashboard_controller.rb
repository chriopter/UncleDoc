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
    @entry_sort = entry_sort_mode(params)
    @available_log_filters = available_log_filters(@person)
    @entries = filtered_entries(@person, @entry_sort)
  end

  def calendar
    @person = Person.find_by!(name: params[:person_slug])
    @year = (params[:year] || Time.zone.today.year).to_i
    @appointments = @person.entries
      .merge(Entry.by_parseable_data_type("appointment"))
      .where(occurred_at: Date.new(@year, 1, 1).beginning_of_day..Date.new(@year, 12, 31).end_of_day)
      .order(occurred_at: :asc)
  end

  def files
    @person = Person.find_by!(name: params[:person_slug])
    @document_entries = @person.entries.with_documents.recent_first
    @document_count = @document_entries.sum(&:document_count)
  end

  def chat
    @person = Person.find_by!(name: params[:person_slug])
    entries = @person.entries.order(occurred_at: :asc)
    preference = user_preference

    error = EntryDataParser.configuration_error_for(preference)
    if error
      render json: { error: I18n.t("log_summary.states.#{error}") } and return
    end

    if entries.blank?
      render json: { error: I18n.t("log_summary.states.no_entries") } and return
    end

    system = LogSummaryGenerator.system_prompt
    patientenakte = build_patientenakte(@person, entries)

    result = LlmChatRequest.call(
      request_kind: "chat",
      preference: preference,
      person: @person,
      messages: [
        { role: "system", content: "#{system}\n\n# Patientenakte: #{@person.name}\n\n#{patientenakte}" },
        { role: "user", content: params[:message].to_s }
      ]
    )

    render json: { reply: result.content }
  rescue StandardError => e
    Rails.logger.warn("Chat failed: #{e.class}: #{e.message}")
    render json: { error: I18n.t("log_summary.states.request_failed") }
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

  def build_patientenakte(person, entries)
    lines = entries.map do |entry|
      date = entry.occurred_at ? I18n.l(entry.occurred_at, format: :long) : "unknown date"
      parts = []
      parts << entry.fact_summary if entry.respond_to?(:fact_summary) && entry.facts.present?
      parts << entry.input if entry.input.present?
      if entry.parseable_data.present?
        data_parts = Array(entry.parseable_data).filter_map do |item|
          next unless item.is_a?(Hash)
          item.map { |k, v| "#{k}: #{v}" }.join(", ")
        end
        parts << data_parts.join("; ") if data_parts.any?
      end
      "- #{date}: #{parts.compact_blank.join(' — ')}"
    end
    lines.join("\n")
  end

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
