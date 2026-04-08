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

  def research
    @person = Person.find_by!(name: params[:person_slug])
    @chat = @person.chat
    @message = Message.new
    @chat_context_preview = @chat&.context_message&.content || ResearchChatContext.system_prompt_for(@person)
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
    all_document_entries = @person.entries.with_documents.recent_first
    @available_file_filters = available_file_filters(all_document_entries)
    @document_entries = filtered_file_entries(all_document_entries)
    @document_count = @document_entries.sum(&:document_count)
    @grouped_document_entries = group_document_entries_by_year(@document_entries)
  end

  def healthkit
    @person = Person.find_by!(name: params[:person_slug])
    @healthkit_syncs = @person.healthkit_syncs.order(updated_at: :desc)
    @healthkit_record_count = @person.healthkit_records.count
    @healthkit_record_type_count = @person.healthkit_records.distinct.count(:record_type)
    healthkit_summary_scope = @person.entries.healthkit_generated
    @healthkit_summary_count = healthkit_summary_scope.count
    @healthkit_daily_summary_count = healthkit_summary_scope.where("source_ref LIKE ?", "healthkit:day:%").count
    @healthkit_monthly_summary_count = healthkit_summary_scope.where("source_ref LIKE ?", "healthkit:month:%").count
    @healthkit_latest_sync = @healthkit_syncs.max_by { |sync| sync.last_synced_at || sync.updated_at || Time.zone.at(0) }
    @healthkit_last_successful_sync_at = @healthkit_syncs.filter_map(&:last_successful_sync_at).max
  end

  def queue_healthkit_summary_sync
    person = Person.find_by!(name: params[:person_slug])
    HealthkitSummarySyncJob.perform_later(person.id)

    redirect_to person_healthkit_path(person_slug: person.name), notice: t("dashboard.healthkit.flash.sync_queued")
  end

  def queue_healthkit_reparse
    person = Person.find_by!(name: params[:person_slug])
    HealthkitSummaryReparseJob.perform_later(person.id)

    redirect_to person_healthkit_path(person_slug: person.name), notice: t("dashboard.healthkit.flash.reparse_queued")
  end

  def summarize_log
    @person = Person.find_by!(name: params[:person_slug])
    @entry = Entry.new
    @entry_sort = entry_sort_mode(params)
    @available_log_filters = available_log_filters(@person)
    @entries = filtered_entries(@person, @entry_sort)

    result = LogSummaryGenerator.call(person: @person, entries: @entries, preference: app_setting)
    @log_summary = result.summary
    @log_summary_state = result.error || :ready

    render turbo_stream: turbo_stream.replace(
      "log_summary_output",
      partial: "dashboard/log_summary_inline",
      locals: { summary: @log_summary, state: @log_summary_state }
    )
  end

  def healthkit_records_page
    @person = Person.find_by!(name: params[:person_slug])
    @healthkit_records_table = healthkit_records_table(@person, page: params[:page])

    if request.format.turbo_stream?
      render turbo_stream: [
        turbo_stream.append("db_table_rows", partial: "dashboard/db_table_rows", locals: { table: @healthkit_records_table }),
        turbo_stream.replace("db_table_pagination", partial: "dashboard/db_table_loader_healthkit", locals: { table: @healthkit_records_table, person: @person })
      ]
    else
      render partial: "dashboard/healthkit_records_table", locals: { table: @healthkit_records_table, person: @person }
    end
  end

  private

  def group_document_entries_by_year(entries)
    entries
      .group_by { |e| e.display_time.year }
      .sort_by { |year, _| -year }
      .map { |year, year_entries|
        types = year_entries
          .group_by { |e| e.document_type.presence || "other" }
          .sort_by { |type, _| type == "other" ? 1 : 0 }
        [year, types]
      }
  end

  def available_file_filters(entries)
    years = entries.map { |e| e.display_time.year }.uniq.sort.reverse
    types = entries.filter_map(&:document_type).uniq.sort
    { years: years, types: types }
  end

  def filtered_file_entries(entries)
    scope = entries

    if params[:year].present?
      year = params[:year].to_i
      scope = scope.select { |e| e.display_time.year == year }
    end

    if params[:doc_type].present?
      scope = scope.select { |e| (e.document_type.presence || "other") == params[:doc_type] }
    end

    scope
  end

  def healthkit_records_table(person, page: 1)
    connection = ActiveRecord::Base.connection
    table_name = "healthkit_records"
    table = Arel::Table.new(table_name)
    columns = connection.columns(table_name).map(&:name)
    primary_key = connection.primary_key(table_name)
    per_page = 250
    current_page = [ page.to_i, 1 ].max
    truncated_columns = %w[payload]

    person_id = person.id
    count_sql = table.project(Arel.star.count).where(table[:person_id].eq(person_id))
    total_count = connection.select_value(count_sql).to_i
    total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
    current_page = [ current_page, total_pages ].min
    offset = (current_page - 1) * per_page

    select_columns = columns.map do |column|
      quoted = connection.quote_column_name(column)

      if column == "payload"
        "CASE WHEN length(#{quoted}) > 400 THEN substr(#{quoted}, 1, 400) || '…' ELSE #{quoted} END AS #{quoted}"
      else
        quoted
      end
    end.join(", ")

    rows_sql = <<~SQL.squish
      SELECT #{select_columns}
      FROM #{connection.quote_table_name(table_name)}
      WHERE #{connection.quote_column_name("person_id")} = #{connection.quote(person_id)}
      ORDER BY #{connection.quote_column_name("start_at")} DESC
      LIMIT #{per_page}
      OFFSET #{offset}
    SQL

    {
      name: table_name,
      columns: columns,
      rows: connection.select_all(rows_sql).to_a,
      count: total_count,
      rendered_count: [ offset + per_page, total_count ].min,
      page: current_page,
      per_page: per_page,
      total_pages: total_pages,
      next_page: current_page < total_pages ? current_page + 1 : nil,
      primary_key: primary_key,
      deletable: false,
      order_column: "start_at",
      truncated_columns: truncated_columns
    }
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

    case params[:source]
    when "manual"
      scope = scope.where(source: Entry::SOURCES[:manual])
    when "babywidget"
      scope = scope.where(source: Entry::SOURCES[:babywidget])
    when "healthkit"
      scope = scope.where(source: Entry::SOURCES[:healthkit])
    when "healthkit_day"
      scope = scope.where(source: Entry::SOURCES[:healthkit]).where("source_ref LIKE ?", "healthkit:day:%")
    when "healthkit_month"
      scope = scope.where(source: Entry::SOURCES[:healthkit]).where("source_ref LIKE ?", "healthkit:month:%")
    end

    scope
  end

  def available_log_filters(person)
    dates = person.entries.order(occurred_at: :desc).pluck(:occurred_at).compact.map(&:to_date).uniq
    types = person.entries.flat_map { |entry| Array(entry.parseable_data).filter_map { |item| item.is_a?(Hash) ? item["type"].presence : nil } }.uniq.sort

    filter_options = types.map { |type| [ "#{type} · #{I18n.t("entries.data_labels.#{type}", default: type.humanize)}", type ] }

    source_options = []
    source_options << [ I18n.t("entries.source.manual"), "manual" ] if person.entries.where(source: Entry::SOURCES[:manual]).exists?
    source_options << [ I18n.t("entries.source.babywidget"), "babywidget" ] if person.entries.where(source: Entry::SOURCES[:babywidget]).exists?
    source_options << [ I18n.t("entries.source.healthkit"), "healthkit" ] if person.entries.where(source: Entry::SOURCES[:healthkit]).exists?
    source_options << [ I18n.t("entries.source.healthkit_day"), "healthkit_day" ] if person.entries.where("source_ref LIKE ?", "healthkit:day:%").exists?
    source_options << [ I18n.t("entries.source.healthkit_month"), "healthkit_month" ] if person.entries.where("source_ref LIKE ?", "healthkit:month:%").exists?

    { dates: dates, parseable_type_options: filter_options, source_options: source_options }
  end
end
