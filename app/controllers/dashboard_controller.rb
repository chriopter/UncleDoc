class DashboardController < ApplicationController
  def show
    @tab = params[:tab].in?(%w[log db]) ? params[:tab] : "log"
    @person = Person.new
    @people = Person.recent_first
    @database_snapshot = database_snapshot if @tab == "db"
  end

  private

  def database_snapshot
    connection = ActiveRecord::Base.connection

    connection.tables.sort.map do |table_name|
      quoted_table = connection.quote_table_name(table_name)

      {
        name: table_name,
        columns: connection.columns(table_name).map(&:name),
        rows: connection.select_all("SELECT * FROM #{quoted_table} LIMIT 50").to_a,
        count: connection.select_value("SELECT COUNT(*) FROM #{quoted_table}").to_i
      }
    end
  end
end
