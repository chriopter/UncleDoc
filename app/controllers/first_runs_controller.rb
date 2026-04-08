class FirstRunsController < ApplicationController
  allow_unauthenticated_access

  before_action :prevent_repeats

  def show
    @person = Person.new
    @user = User.new
  end

  def create
    user = FirstRun.create!(**first_run_params)
    start_new_session_for(user)
    redirect_to root_path, notice: t("auth.first_run.created")
  rescue ActiveRecord::RecordInvalid => error
    @user = error.record.is_a?(User) ? error.record : nil
    @person = error.record.is_a?(Person) ? error.record : Person.new(name: first_run_params[:person_name], birth_date: first_run_params[:birth_date])
    flash.now[:alert] = error.record.errors.full_messages.to_sentence
    render :show, status: :unprocessable_entity
  end

  private

  def prevent_repeats
    redirect_to new_session_path if User.any? || Person.any?
  end

  def first_run_params
    params.require(:setup).permit(:person_name, :birth_date, :email_address, :password, :password_confirmation).to_h.symbolize_keys
  end
end
