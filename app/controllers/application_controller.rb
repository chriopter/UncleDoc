class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_locale_from_preferences
  before_action :load_family_members
  before_action :set_current_person
  before_action :initialize_entry_for_current_person

  helper_method :current_date_format, :current_locale, :current_llm_provider, :current_person, :family_members, :person_root_path_for, :settings_path_for, :user_preference, :baby_feeding_timer_started_at_for, :baby_feeding_timer_side_for, :baby_sleep_timer_started_at_for

  def default_url_options
    {}
  end

  private

  def set_locale_from_preferences
    I18n.locale = current_locale
  end

  def load_family_members
    @family_members = Person.recent_first
  end

  def set_current_person
    if params[:person_slug].present?
      @current_person = Person.find_by(name: params[:person_slug])
    elsif @family_members.any?
      @current_person = @family_members.first
    end
  end

  def current_person
    @current_person
  end

  def family_members
    @family_members
  end

  def person_root_path_for(person)
    root_path(person_slug: person&.name)
  end

  def settings_path_for(section = nil)
    settings_path({ section: section, locale: params[:locale].presence, date_format: params[:date_format].presence }.compact)
  end

  def initialize_entry_for_current_person
    if current_person
      @entry = Entry.new
      @entries = current_person.entries.recent_first
    end
  end

  def current_locale
    if params[:locale].present? && %w[en de].include?(params[:locale])
      params[:locale]
    else
      user_preference.locale
    end
  end

  def current_date_format
    user_preference.date_format
  end

  def current_llm_provider
    if params[:llm_provider].present? && UserPreference::LLM_PROVIDERS.key?(params[:llm_provider])
      params[:llm_provider]
    else
      user_preference.llm_provider
    end
  end

  def user_preference
    @user_preference ||= UserPreference.current
  end

  def baby_feeding_timer_started_at_for(person)
    person.baby_feeding_timer_started_at
  end

  def baby_feeding_timer_side_for(person)
    person.baby_feeding_timer_side.presence || "left"
  end

  def baby_sleep_timer_started_at_for(person)
    person.baby_sleep_timer_started_at
  end
end
