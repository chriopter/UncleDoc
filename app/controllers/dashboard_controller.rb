class DashboardController < ApplicationController
  def show
    @person = Person.new
    @people = Person.recent_first

    if current_person
      @entry = Entry.new
      @entries = current_person.entries.recent_first
    end
  end

  def log
    @person = Person.find_by!(name: params[:person_slug])
    @entry = Entry.new
    @entries = @person.entries.recent_first
  end
end
