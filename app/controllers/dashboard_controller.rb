class DashboardController < ApplicationController
  def show
    @person = Person.new
    @people = Person.recent_first
  end
end
