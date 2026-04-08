class SettingsController < ApplicationController
  require_admin_access

  def show
    save_preferences if params[:locale].present? || params[:llm_provider].present?

    @section = params[:section].in?(%w[llm llm_prompt llm_prompt_preview db db_table users]) ? params[:section] : "users"
    @database_table = database_table_detail(params[:table], page: params[:page]) if @section == "db_table" && params[:table].present?
    if @section == "users"
      @people = Person.recent_first
      @person = Person.new
      @person.build_user(admin: false)
    end

    return unless llm_section?

    @llm_stats = llm_stats
    load_prompt_preview
  end

  def update
    UserPreference.update_date_format(params[:date_format]) if params[:date_format].present?
    save_preferences

    redirect_to settings_path(section: resolved_section), notice: t("settings.flash.saved")
  end

  def destroy_db_row
    table_name = params[:table].to_s
    row_id = params[:row_id].to_s
    detail = database_table_detail(table_name, page: params[:page])

    return redirect_to(settings_path(section: "db"), alert: t("db.table.delete_unavailable")) unless detail&.dig(:deletable)

    delete_database_row!(table_name, row_id, detail[:primary_key])

    redirect_to settings_path(section: "db_table", table: table_name, page: params[:page]), notice: t("db.table.delete_success", table: table_name, id: row_id)
  rescue ActiveRecord::RecordNotFound
    redirect_to settings_path(section: "db_table", table: table_name, page: params[:page]), alert: t("db.table.delete_missing", table: table_name, id: row_id)
  rescue StandardError => error
    redirect_to settings_path(section: "db_table", table: table_name, page: params[:page]), alert: t("db.table.delete_failed", message: error.message)
  end

  def llm_test
    preference = app_setting
    error = EntryDataParser.configuration_error_for(preference)
    if error
      render json: { error: I18n.t("log_summary.states.#{error}") } and return
    end

    result = LlmChatRequest.call(
      request_kind: "test",
      preference: preference,
      messages: [
        { role: "user", content: "Say hi in one sentence." }
      ]
    )

    render json: { reply: result.content }
  rescue StandardError => e
    render json: { error: e.message.truncate(120) }
  end

  def prompt_preview
    person = Person.find(params[:person_id])
    kind = params[:kind]

    text = case kind
    when "parser"
      system = EntryDataParser.system_prompt
      user = EntryDataParser.user_prompt("Example input: 38.2 Fieber")
      "=== SYSTEM ===\n\n#{system}\n\n=== USER ===\n\n#{user}"
    when "summary"
      entries = person.entries.order(occurred_at: :desc)
      system = LogSummaryGenerator.system_prompt
      user = LogSummaryGenerator.summary_prompt(person, entries)
      "=== SYSTEM ===\n\n#{system}\n\n=== USER ===\n\n#{user}"
    else
      "Unknown prompt kind: #{kind}"
    end

    render plain: text
  end

  def llm_models
    provider = params[:llm_provider].presence || AppSetting.current.llm_provider
    metadata = AppSetting.provider_metadata(provider)
    api_key = params[:llm_api_key].presence || AppSetting.current.llm_api_key || ENV[metadata[:env_key]]
    api_base = metadata[:env_base_key].present? ? ENV[metadata[:env_base_key]].presence || metadata[:api_base] : metadata[:api_base]
    result = LlmModelCatalog.lookup(provider: provider, api_key: api_key, api_base: api_base)

    render json: {
      models: result.models,
      selected_model: selected_llm_model(result.models),
      env_key: metadata[:env_key],
      api_base: api_base,
      status: llm_model_status(provider, result),
      empty_label: t("settings.llm.model_empty")
    }
  end

  private

  def save_preferences
    UserPreference.update_locale(params[:locale]) if params[:locale].present?

    return unless params[:llm_provider].present? || params[:llm_api_key].present? || params[:llm_model].present?

    AppSetting.update_llm_settings(
      llm_provider: params[:llm_provider].presence || AppSetting.current.llm_provider,
      llm_api_key: params[:llm_api_key],
      llm_model: params[:llm_model]
    )
  end

  def resolved_section
    params[:section].in?(%w[llm llm_prompt llm_prompt_preview db db_table users]) ? params[:section] : "users"
  end

  def llm_section?
    @section.in?(%w[llm llm_prompt llm_prompt_preview])
  end

  def llm_stats
    {
      total_requests: Chat.count,
      parse_requests: Message.where(role: "user").count,
      summary_requests: Message.where(role: "assistant").count,
      latest_request_at: Message.maximum(:created_at)
    }
  end

  def selected_llm_model(models)
    preferred_model = params[:llm_model].presence || AppSetting.current.llm_model
    return preferred_model if preferred_model.present? && models.include?(preferred_model)

    models.first
  end

  def llm_model_status(provider, result)
    return t("settings.llm.model_status.unsupported", provider: t("settings.llm.providers.#{provider}.name")) if result.error == :unsupported_provider
    return t("settings.llm.model_status.missing_key") if result.error == :missing_api_key
    return t("settings.llm.model_status.request_failed") if result.error.in?([ :missing_api_base, :request_failed, :unauthorized ])
    return t("settings.llm.model_status.empty") if result.models.empty?

    t("settings.llm.model_status.loaded", count: result.models.size)
  end

  def load_prompt_preview
    @preview_people = Person.recent_first
    @preview_person = if params[:preview_person_id].present?
      @preview_people.find { |person| person.id == params[:preview_person_id].to_i }
    else
      @preview_people.first
    end

    entries = @preview_person ? @preview_person.entries.order(occurred_at: :desc).limit(5) : Entry.none

    @prompt_previews = {
      parser: {
        system: EntryDataParser.system_prompt,
        user: EntryDataParser.user_prompt("Example input: 38.2 Fieber")
      },
      summary: {
        system: LogSummaryGenerator.system_prompt,
        user: @preview_person ? LogSummaryGenerator.summary_prompt(@preview_person, entries) : t("settings.llm.prompt_preview_empty")
      }
    }
  end

  def database_table_detail(table_name, page: 1)
    connection = ActiveRecord::Base.connection
    return nil unless connection.tables.include?(table_name)

    table = Arel::Table.new(table_name)
    columns = connection.columns(table_name).map(&:name)
    primary_key = connection.primary_key(table_name)
    per_page = 50
    current_page = [ page.to_i, 1 ].max
    total_count = connection.select_value(table.project(Arel.star.count)).to_i
    total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
    current_page = [ current_page, total_pages ].min
    offset = (current_page - 1) * per_page
    order_column = primary_key.presence || (columns.include?("created_at") ? "created_at" : (columns.include?("updated_at") ? "updated_at" : nil))
    rows_query = table.project(Arel.star).take(per_page).skip(offset)
    rows_query = rows_query.order(table[order_column].desc) if order_column.present?

    {
      name: table_name,
      columns: columns,
      rows: connection.select_all(rows_query).to_a,
      count: total_count,
      rendered_count: [ offset + per_page, total_count ].min,
      page: current_page,
      per_page: per_page,
      total_pages: total_pages,
      next_page: current_page < total_pages ? current_page + 1 : nil,
      primary_key: primary_key,
      deletable: database_table_deletable?(table_name, primary_key),
      order_column: order_column
    }
  end

  def database_table_deletable?(table_name, primary_key)
    primary_key.present? && !%w[app_settings ar_internal_metadata schema_migrations user_preferences].include?(table_name)
  end

  def delete_database_row!(table_name, row_id, primary_key)
    model = database_table_record_model(table_name, primary_key)

    if model
      model.find(row_id).destroy!
      return
    end

    connection = ActiveRecord::Base.connection
    deleted = connection.delete(
      "DELETE FROM #{connection.quote_table_name(table_name)} WHERE #{connection.quote_column_name(primary_key)} = #{connection.quote(row_id)}"
    )
    raise ActiveRecord::RecordNotFound if deleted.zero?
  end

  def database_table_record_model(table_name, primary_key)
    model = table_name.classify.safe_constantize
    return nil unless model&.ancestors&.include?(ApplicationRecord)
    return nil unless model.table_name == table_name && model.primary_key == primary_key

    model
  end
end
