class BabyFeedingTimersController < ApplicationController
  before_action :set_person

  def create
    if baby_feeding_timer_started_at.present?
      redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), notice: t("baby.feeding.timer.already_running")
      return
    end

    session["baby_feeding_timers"] ||= {}
    session["baby_feeding_timers"][@person.id.to_s] = {
      "started_at" => Time.current.iso8601,
      "side" => feeding_side
    }

    redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), notice: t("baby.feeding.timer.started", side: t("baby.feeding.sides.#{feeding_side}"))
  end

  def destroy
    started_at = baby_feeding_timer_started_at

    if started_at.blank?
      redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), alert: t("baby.feeding.timer.missing")
      return
    end

    duration_minutes = [ ((Time.current - started_at) / 60).round, 1 ].max
    side = baby_feeding_timer_side

    @person.entries.create!(
      occurred_at: Time.current,
      note: t("baby.feeding.timer.note", side: t("baby.feeding.sides.#{side}"), duration: duration_minutes),
      data: [ { "type" => "breast_feeding", "value" => duration_minutes, "unit" => "min", "side" => side } ]
    )

    session["baby_feeding_timers"].delete(@person.id.to_s)

    redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), notice: t("baby.feeding.timer.stopped")
  end

  private

  def set_person
    @person = Person.find(params[:person_id])
  end

  def baby_feeding_timer_started_at
    started_at = session.dig("baby_feeding_timers", @person.id.to_s, "started_at")
    return if started_at.blank?

    Time.zone.parse(started_at)
  rescue ArgumentError
    nil
  end

  def baby_feeding_timer_side
    session.dig("baby_feeding_timers", @person.id.to_s, "side") || "left"
  end

  def feeding_side
    params[:side].in?(%w[left right]) ? params[:side] : "left"
  end
end
