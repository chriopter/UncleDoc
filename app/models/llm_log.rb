class LlmLog < ApplicationRecord
  belongs_to :person, optional: true
  belongs_to :entry, optional: true

  validates :request_kind, presence: true
  validates :provider, presence: true
  validates :endpoint, presence: true
  validates :request_payload, presence: true
end
