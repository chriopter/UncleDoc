class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_locale_from_preferences
  around_action :use_browser_time_zone
  before_action :load_family_members
  before_action :set_current_person
  before_action :initialize_entry_for_current_person

  helper_method :app_setting, :current_date_format, :current_locale, :current_llm_provider, :current_native_app_token, :current_person, :family_members, :person_root_path_for, :settings_path_for, :user_preference, :baby_feeding_timer_started_at_for, :baby_feeding_timer_side_for, :baby_sleep_timer_started_at_for

  def default_url_options
    {}
  end

  private

  def set_locale_from_preferences
    I18n.locale = current_locale
  end

  def use_browser_time_zone(&block)
    zone_name = browser_time_zone_name
    zone = zone_name.present? ? ActiveSupport::TimeZone[zone_name] : nil
    zone ? Time.use_zone(zone, &block) : yield
  end

  def load_family_members
    @family_members = current_user.present? ? Person.recent_first : []
  end

  def set_current_person
    if params[:person_slug].present?
      @current_person = Person.find_by(name: params[:person_slug])
    elsif Current.user_person.present?
      @current_person = Current.user_person
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
    if params[:date_format].present? && %w[long compact].include?(params[:date_format])
      params[:date_format]
    else
      user_preference.date_format
    end
  end

  def current_llm_provider
    if params[:llm_provider].present? && AppSetting::LLM_PROVIDERS.key?(params[:llm_provider])
      params[:llm_provider]
    else
      app_setting.llm_provider
    end
  end

  def app_setting
    @app_setting ||= AppSetting.current
  end

  def current_native_app_token
    return unless request.user_agent.to_s.include?("UncleDoc iOS") && current_user.present?

    @current_native_app_token ||= current_user.ensure_native_app_token!
  end

  def browser_time_zone_name
    params[:time_zone].presence || cookies[:browser_time_zone].presence || request.headers["X-Time-Zone"].presence
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
