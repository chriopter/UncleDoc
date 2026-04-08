class BabySleepTimersController < ApplicationController
  before_action :set_person
  before_action :ensure_baby_mode

  def create
    started = false

    @person.with_lock do
      @person.reload
      if @person.baby_sleep_timer_started_at.present?
        redirect_back fallback_location: person_baby_path(person_slug: @person.name), notice: t("baby.sleep.timer.already_running")
        return
      end

      @person.update!(baby_sleep_timer_started_at: Time.current)
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
      started_at = @person.baby_sleep_timer_started_at

      if started_at.blank?
        redirect_back fallback_location: person_baby_path(person_slug: @person.name), alert: t("baby.sleep.timer.missing")
        return
      end

      duration_minutes = [ ((Time.current - started_at) / 60).round, 1 ].max

      @person.entries.create!(
        occurred_at: Time.current,
        input: t("baby.sleep.timer.note", duration: duration_minutes),
        extracted_data: { "facts" => EntryFactListBuilder.fact_objects([ { "type" => "sleep", "value" => duration_minutes, "unit" => "min" } ]), "document" => {}, "llm" => {} },
        parse_status: "parsed",
        source: Entry::SOURCES[:babywidget]
      )

      @person.update!(baby_sleep_timer_started_at: nil)
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
end
