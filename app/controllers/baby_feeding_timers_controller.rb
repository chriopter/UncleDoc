class BabyFeedingTimersController < ApplicationController
  before_action :set_person
  before_action :ensure_baby_mode

  def create
    started = false

    @person.with_lock do
      @person.reload
      if @person.baby_feeding_timer_started_at.present?
        redirect_back fallback_location: person_baby_path(person_slug: @person.name), notice: t("baby.feeding.timer.already_running")
        return
      end

      @person.update!(baby_feeding_timer_started_at: Time.current, baby_feeding_timer_side: feeding_side)
      started = true
    end

    return unless started

    BabyDashboardBroadcaster.broadcast(@person.reload)

    respond_to do |format|
      format.html { redirect_back fallback_location: person_baby_path(person_slug: @person.name) }
      format.turbo_stream { render "shared/baby_action_update" }
    end
  end

  def destroy
    stopped = false

    @person.with_lock do
      @person.reload
      started_at = @person.baby_feeding_timer_started_at

      if started_at.blank?
        redirect_back fallback_location: person_baby_path(person_slug: @person.name), alert: t("baby.feeding.timer.missing")
        return
      end

      duration_minutes = [ ((Time.current - started_at) / 60).round, 1 ].max
      side = @person.baby_feeding_timer_side.presence || "left"

      @person.entries.create!(
        occurred_at: Time.current,
        input: t("baby.feeding.timer.note", side: t("baby.feeding.sides.#{side}"), duration: duration_minutes),
        extracted_data: { "facts" => EntryFactListBuilder.fact_objects([ { "type" => "breast_feeding", "value" => duration_minutes, "unit" => "min", "side" => side } ]), "llm" => {} },
        parse_status: "parsed",
        source: Entry::SOURCES[:babywidget]
      )

      @person.update!(baby_feeding_timer_started_at: nil, baby_feeding_timer_side: nil)
      stopped = true
    end

    return unless stopped

    BabyDashboardBroadcaster.broadcast(@person.reload)

    respond_to do |format|
      format.html { redirect_back fallback_location: person_baby_path(person_slug: @person.name) }
      format.turbo_stream { render "shared/baby_action_update" }
    end
  end

  private

  def set_person
    @person = Person.find(params[:person_id])
  end

  def ensure_baby_mode
    head :not_found unless @person.baby_mode?
  end

  def feeding_side
    params[:side].in?(%w[left right]) ? params[:side] : "left"
  end
end
