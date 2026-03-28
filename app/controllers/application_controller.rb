class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_date_format, :current_locale

  def default_url_options
    {}.tap do |options|
      options[:locale] = current_locale if current_locale == "de"
      options[:date_format] = current_date_format if current_date_format != "long"
    end
  end

  private

  def current_locale
    params[:locale].in?(%w[en de]) ? params[:locale] : "en"
  end

  def current_date_format
    params[:date_format].in?(%w[long compact]) ? params[:date_format] : "long"
  end
end
