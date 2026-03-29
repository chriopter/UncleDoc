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
    @log_summary_state = :idle
  end

  def summarize_log
    @person = Person.find_by!(name: params[:person_slug])
    @entry = Entry.new
    @entries = @person.entries.recent_first

    result = LogSummaryGenerator.call(person: @person, entries: @entries, preference: user_preference)
    @log_summary = result.summary
    @log_summary_state = result.error || :ready

    render turbo_stream: turbo_stream.replace(
      "log_summary_output",
      partial: "dashboard/log_summary_inline",
      locals: { summary: @log_summary, state: @log_summary_state }
    )
  end
end
