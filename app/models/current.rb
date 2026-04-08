class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true
  delegate :person, to: :user, prefix: true, allow_nil: true
end
