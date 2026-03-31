class SettingsController < ApplicationController
  def show
    save_preferences if params[:locale].present? || params[:llm_provider].present?

    @section = params[:section].in?(%w[profile llm llm_prompt llm_logs db users]) ? params[:section] : "profile"
    @database_snapshot = database_snapshot if @section == "db"
    @people = Person.recent_first if @section == "users"
    @person = Person.new if @section == "users"
    @llm_logs = LlmLog.order(created_at: :desc).limit(200) if @section == "llm_logs"
    @llm_stats = llm_stats if @section == "llm"
  end

  def update
    UserPreference.update_date_format(params[:date_format]) if params[:date_format].present?
    save_preferences

    redirect_to settings_path(section: resolved_section), notice: t("settings.flash.saved")
  end

  def llm_models
    provider = params[:llm_provider].presence || UserPreference.current.llm_provider
    metadata = UserPreference.provider_metadata(provider)
    api_key = params[:llm_api_key].presence || UserPreference.current.llm_api_key || ENV[metadata[:env_key]]
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
    UserPreference.update_llm_provider(params[:llm_provider]) if params[:llm_provider].present?

    return unless params[:llm_provider].present? || params[:llm_api_key].present? || params[:llm_model].present?

    UserPreference.update_llm_settings(
      llm_provider: params[:llm_provider].presence || UserPreference.current.llm_provider,
      llm_api_key: params[:llm_api_key],
      llm_model: params[:llm_model]
    )
  end

  def resolved_section
    params[:section].in?(%w[profile llm llm_prompt llm_logs db users]) ? params[:section] : "profile"
  end

  def llm_stats
    scope = LlmLog.all

    {
      total_requests: scope.count,
      parse_requests: scope.where(request_kind: "entry_parse").count,
      summary_requests: scope.where(request_kind: "log_summary").count,
      latest_request_at: scope.maximum(:created_at)
    }
  end

  def selected_llm_model(models)
    preferred_model = params[:llm_model].presence || UserPreference.current.llm_model
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

  def database_snapshot
    connection = ActiveRecord::Base.connection

    tables = connection.tables.sort.map do |table_name|
      quoted_table = connection.quote_table_name(table_name)

      {
        name: table_name,
        columns: connection.columns(table_name).map(&:name),
        rows: connection.select_all("SELECT * FROM #{quoted_table} LIMIT 200").to_a,
        count: connection.select_value("SELECT COUNT(*) FROM #{quoted_table}").to_i
      }
    end

    # Group tables into data and system tables
    data_tables = %w[entries people llm_logs]
    system_tables = %w[ar_internal_metadata schema_migrations user_preferences]

    {
      all: tables,
      data: tables.select { |t| data_tables.include?(t[:name]) },
      system: tables.select { |t| system_tables.include?(t[:name]) }
    }
  end
end
