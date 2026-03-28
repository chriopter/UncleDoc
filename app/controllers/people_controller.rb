class PeopleController < ApplicationController
  def create
    @person = Person.new(person_params)

    if @person.save
      @people = Person.recent_first
      @fresh_person = Person.new

      respond_to do |format|
        format.html { redirect_to root_path(tab: "log"), notice: "Person added." }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html do
          @tab = "log"
          @people = Person.recent_first
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

    respond_to do |format|
      format.html { redirect_to root_path(tab: "log"), notice: "Person removed." }
      format.turbo_stream
    end
  end

  private

  def person_params
    params.require(:person).permit(:name, :birth_date)
  end
end
