class PeopleController < ApplicationController
  def show
    @person = Person.find_by!(name: params[:person_slug])
    @entry_sort = params[:sort].to_s == "entered" ? "entered" : "occurred"
    @entries = @person.entries.merge(Entry.sorted_by(@entry_sort)).limit(5)
    @entry_count = @person.entries.count
    @entry = Entry.new
  end

  def trends
    @person = Person.find_by!(name: params[:person_slug])
  end

  def baby
    @person = Person.find_by!(name: params[:person_slug])
    head :not_found and return unless @person.baby_mode?

    @entry = Entry.new
    @entry_sort = params[:sort].to_s == "entered" ? "entered" : "occurred"
    @entries = @person.entries.merge(Entry.sorted_by(@entry_sort)).limit(10)
  end

  def create
    @person = Person.new(person_params)

    if @person.save
      @people = Person.recent_first
      @fresh_person = Person.new

      respond_to do |format|
        format.html { redirect_to root_path(person_slug: @person.name, tab: "log"), notice: t("people.flash.created") }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html do
          @tab = "log"
          @people = Person.recent_first
          # When validation fails, show empty state - no current person selected
          @entry = Entry.new
          render "dashboard/show", status: :unprocessable_entity
        end

        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "person_form",
            partial: "people/form",
            locals: { person: @person }
          ), status: :unprocessable_entity
        end
      end
    end
  end

  def update
    @person = Person.find(params[:id])

    if @person.update(person_params)
      redirect_to request.referer || person_overview_path(person_slug: @person.name), notice: t("people.flash.updated")
    else
      redirect_to request.referer || settings_path(section: "users"), alert: t("people.flash.update_error")
    end
  end

  def destroy
    @person = Person.find(params[:id])
    if @person.destroy
      @people = Person.recent_first

      # After deleting a person, switch to another family member or go to root
      remaining_person = @people.first

      respond_to do |format|
        format.html { redirect_to root_path(person_slug: remaining_person&.name, tab: "log"), notice: t("people.flash.destroyed") }
        format.turbo_stream
      end
    else
      redirect_to request.referer || settings_path(section: "users"), alert: t("people.flash.destroy_error")
    end
  end

  private

  def person_params
    params.require(:person).permit(:name, :birth_date, :baby_mode, :locale, :date_format)
  end
end
