class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :load_family_members
  before_action :set_current_person
  before_action :initialize_entry_for_current_person

  helper_method :current_date_format, :current_locale, :current_person, :family_members, :person_root_path_for

  def default_url_options
    {}.tap do |options|
      options[:locale] = current_locale if current_locale == "de"
      options[:date_format] = current_date_format if current_date_format != "long"
      options[:person_slug] = current_person&.name if current_person
    end
  end

  private

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

  def initialize_entry_for_current_person
    if current_person
      @entry = Entry.new
      @entries = current_person.entries.recent_first
    end
  end

  def current_locale
    params[:locale].in?(%w[en de]) ? params[:locale] : "en"
  end

  def current_date_format
    params[:date_format].in?(%w[long compact]) ? params[:date_format] : "long"
  end
end
