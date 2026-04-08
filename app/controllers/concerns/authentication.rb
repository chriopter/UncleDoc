module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_session, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      current_user.present?
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      return Current.session if Current.session.present?

      if (session = find_session_by_cookie)
        session.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
        Current.session = session
      end
    end

    def find_session_by_cookie
      Session.find_by(token: cookies.signed[:session_token]) if cookies.signed[:session_token]
    end

    def current_session
      Current.session
    end

    def current_user
      Current.user
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to(setup_required? ? first_run_path : new_session_path)
    end

    def setup_required?
      User.none? && Person.none?
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      terminate_session if Current.session.present?
      reset_session

      Session.start!(user:, user_agent: request.user_agent, ip_address: request.remote_ip).tap do |new_session|
        user.update_column(:last_signed_in_at, Time.current)
        Current.session = new_session
        cookies.signed.permanent[:session_token] = { value: new_session.token, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session&.destroy!
      Current.session = nil
      reset_session
      cookies.delete(:session_token)
    end
end
