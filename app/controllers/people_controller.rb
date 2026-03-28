class PeopleController < ApplicationController
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

  def destroy
    @person = Person.find(params[:id])
    @person.destroy
    @people = Person.recent_first

    # After deleting a person, switch to another family member or go to root
    remaining_person = @people.first

    respond_to do |format|
      format.html { redirect_to root_path(person_slug: remaining_person&.name, tab: "log"), notice: t("people.flash.destroyed") }
      format.turbo_stream
    end
  end

  private

  def person_params
    params.require(:person).permit(:name, :birth_date)
  end
end
