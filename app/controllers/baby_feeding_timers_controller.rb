class BabyFeedingTimersController < ApplicationController
  before_action :set_person

  def create
    if baby_feeding_timer_started_at.present?
      redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), notice: t("baby.feeding.timer.already_running")
      return
    end

    session["baby_feeding_timers"] ||= {}
    session["baby_feeding_timers"][@person.id.to_s] = Time.current.iso8601

    redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), notice: t("baby.feeding.timer.started")
  end

  def destroy
    started_at = baby_feeding_timer_started_at

    if started_at.blank?
      redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), alert: t("baby.feeding.timer.missing")
      return
    end

    duration_minutes = [ ((Time.current - started_at) / 60).round, 1 ].max

    @person.entries.create!(
      entry_type: "baby_feeding",
      date: Time.zone.today,
      note: t("baby.feeding.timer.note", duration: duration_minutes),
      metadata: { "duration_minutes" => duration_minutes }
    )

    session["baby_feeding_timers"].delete(@person.id.to_s)

    redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), notice: t("baby.feeding.timer.stopped")
  end

  private

  def set_person
    @person = Person.find(params[:person_id])
  end

  def baby_feeding_timer_started_at
    started_at = session.dig("baby_feeding_timers", @person.id.to_s)
    return if started_at.blank?

    Time.zone.parse(started_at)
  rescue ArgumentError
    nil
  end
end
