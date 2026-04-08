module Authorization
  extend ActiveSupport::Concern

  class_methods do
    def require_admin_access(**options)
      before_action :require_admin, **options
    end
  end

  private

  def require_admin
    return if current_user&.can_administer?

    redirect_to root_path, alert: t("auth.forbidden")
  end
end
