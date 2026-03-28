class SettingsController < ApplicationController
  def show
    save_preferences if params[:locale].present? || params[:date_format].present?

    @section = params[:section].in?(%w[profile db users]) ? params[:section] : "profile"
    @database_snapshot = database_snapshot if @section == "db"
    @people = Person.recent_first if @section == "users"
    @person = Person.new if @section == "users"
  end

  private

  def save_preferences
    UserPreference.update_locale(params[:locale]) if params[:locale].present?
    UserPreference.update_date_format(params[:date_format]) if params[:date_format].present?
  end

  def database_snapshot
    connection = ActiveRecord::Base.connection

    connection.tables.sort.map do |table_name|
      quoted_table = connection.quote_table_name(table_name)

      {
        name: table_name,
        columns: connection.columns(table_name).map(&:name),
        rows: connection.select_all("SELECT * FROM #{quoted_table} LIMIT 200").to_a,
        count: connection.select_value("SELECT COUNT(*) FROM #{quoted_table}").to_i
      }
    end
  end
end
