class BabyQuickActionsController < ApplicationController
  before_action :set_person
  before_action :ensure_baby_mode

  def diaper
    payload = diaper_payload
    @person.entries.create!(
      occurred_at: Time.current,
      input: diaper_note,
      extracted_data: { "facts" => EntryFactListBuilder.fact_objects([ payload ]), "llm" => {} },
      parse_status: "parsed",
      source: Entry::SOURCES[:babywidget]
    )

    respond_to do |format|
      format.html { redirect_back fallback_location: person_baby_path(person_slug: @person.name) }
      format.turbo_stream { render "shared/baby_action_update" }
    end
  end

  def bottle
    amount = params[:amount_ml].to_i
    if amount <= 0
      redirect_back fallback_location: root_path(person_slug: @person.name, tab: "log"), alert: t("baby.bottle.invalid_amount")
      return
    end

    @person.entries.create!(
      occurred_at: Time.current,
      input: t("baby.bottle.note", amount: amount),
      extracted_data: { "facts" => EntryFactListBuilder.fact_objects([ { "type" => "bottle_feeding", "value" => amount, "unit" => "ml" } ]), "llm" => {} },
      parse_status: "parsed",
      source: Entry::SOURCES[:babywidget]
    )

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

  def diaper_payload
    case params[:kind]
    when "wet"
      { "type" => "diaper", "wet" => true, "solid" => false }
    when "solid"
      { "type" => "diaper", "wet" => false, "solid" => true }
    else
      { "type" => "diaper", "wet" => true, "solid" => true }
    end
  end

  def diaper_note
    case params[:kind]
    when "wet"
      t("baby.diaper.notes.wet")
    when "solid"
      t("baby.diaper.notes.solid")
    else
      t("baby.diaper.notes.both")
    end
  end
end
