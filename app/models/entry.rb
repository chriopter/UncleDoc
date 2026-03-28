class Entry < ApplicationRecord
  belongs_to :person

  validates :date, presence: true
  validates :note, presence: true
  validates :entry_type, inclusion: { in: -> { EntryTypeService.all.keys }, allow_blank: true }
  validate :metadata_matches_definition

  # Store metadata fields as accessors
  store_accessor :metadata

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }
  scope :baby_feedings, -> { where(entry_type: "baby_feeding") }
  scope :baby_diapers, -> { where(entry_type: "baby_diaper") }
  scope :by_type, ->(type) { where(entry_type: type) }

  def baby_feeding?
    entry_type == "baby_feeding"
  end

  def baby_diaper?
    entry_type == "baby_diaper"
  end

  def entry_type_definition
    EntryTypeService.find(entry_type)
  end

  def metadata_field_value(field_name)
    metadata&.dig(field_name.to_s)
  end

  def diaper_consistency
    metadata_field_value("consistency") if baby_diaper?
  end

  def diaper_rash?
    metadata_field_value("rash") == "true" if baby_diaper?
  end

  def self.last_feeding_for(person)
    where(person: person).baby_feedings.recent_first.first
  end

  def self.last_diaper_for(person)
    where(person: person).baby_diapers.recent_first.first
  end

  def time_since
    return nil unless created_at
    Time.current - created_at
  end

  private

  def metadata_matches_definition
    return if entry_type.blank? || metadata.blank?

    definition = entry_type_definition
    return unless definition

    fields = definition["fields"] || {}

    # Validate that metadata keys match defined fields
    metadata.each do |key, value|
      unless fields.key?(key.to_s)
        errors.add(:metadata, "contains unknown field: #{key}")
      end
    end
  end
end
