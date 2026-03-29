class SimplifyEntriesToNoteAndData < ActiveRecord::Migration[8.1]
  class MigrationEntry < ApplicationRecord
    self.table_name = "entries"
  end

  def up
    add_column :entries, :data, :json, default: [] unless column_exists?(:entries, :data)
    add_column :entries, :occurred_at, :datetime unless column_exists?(:entries, :occurred_at)

    MigrationEntry.reset_column_information

    MigrationEntry.find_each do |entry|
      entry.update_columns(
        data: migrated_data_for(entry),
        occurred_at: migrated_occurred_at_for(entry)
      )
    end

    change_column_null :entries, :occurred_at, false

    remove_column :entries, :entry_type, :string if column_exists?(:entries, :entry_type)
    remove_column :entries, :metadata, :json if column_exists?(:entries, :metadata)
    remove_column :entries, :date, :date if column_exists?(:entries, :date)
  end

  def down
    add_column :entries, :date, :date unless column_exists?(:entries, :date)
    add_column :entries, :entry_type, :string unless column_exists?(:entries, :entry_type)
    add_column :entries, :metadata, :json, default: {} unless column_exists?(:entries, :metadata)

    MigrationEntry.reset_column_information

    MigrationEntry.find_each do |entry|
      entry.update_columns(
        date: entry.occurred_at&.to_date || Date.current,
        entry_type: nil,
        metadata: {}
      )
    end

    change_column_null :entries, :date, false

    remove_column :entries, :occurred_at, :datetime if column_exists?(:entries, :occurred_at)
    remove_column :entries, :data, :json if column_exists?(:entries, :data)
  end

  private

  def migrated_occurred_at_for(entry)
    entry.created_at || Time.zone.local(entry.date.year, entry.date.month, entry.date.day, 12, 0, 0)
  rescue NoMethodError
    entry.created_at || Time.current
  end

  def migrated_data_for(entry)
    metadata = (entry.metadata || {}).deep_stringify_keys

    case entry.entry_type
    when "baby_feeding"
      feeding_data(metadata)
    when "baby_diaper"
      [ diaper_data(metadata) ]
    when "baby_sleep"
      [ compact_hash("type" => "sleep", "value" => numeric_value(metadata["duration_minutes"]), "unit" => (metadata["duration_minutes"].present? ? "min" : nil), "quality" => metadata["quality"]) ]
    when "health_temperature"
      [ compact_hash("type" => "temperature", "value" => numeric_value(metadata["celsius"]), "unit" => (metadata["celsius"].present? ? "C" : nil), "location" => metadata["location"]) ]
    when "health_pulse"
      [ compact_hash("type" => "pulse", "value" => numeric_value(metadata["bpm"]), "unit" => (metadata["bpm"].present? ? "bpm" : nil), "location" => metadata["activity"]) ]
    else
      []
    end.reject(&:blank?)
  end

  def feeding_data(metadata)
    if metadata["amount_ml"].present? || metadata["method"] == "bottle"
      [ compact_hash("type" => "bottle_feeding", "value" => numeric_value(metadata["amount_ml"]), "unit" => (metadata["amount_ml"].present? ? "ml" : nil)) ]
    elsif metadata["duration_minutes"].present? || metadata["method"] == "breast"
      [ compact_hash("type" => "breast_feeding", "value" => numeric_value(metadata["duration_minutes"]), "unit" => (metadata["duration_minutes"].present? ? "min" : nil)) ]
    else
      [ compact_hash("type" => "baby_feeding") ]
    end
  end

  def diaper_data(metadata)
    wet, solid =
      case metadata["consistency"]
      when "solid"
        [ false, true ]
      when "fluid", "none"
        [ true, false ]
      when "both"
        [ true, true ]
      else
        [ nil, nil ]
      end

    compact_hash("type" => "diaper", "wet" => wet, "solid" => solid, "rash" => metadata["rash"] == "true")
  end

  def compact_hash(hash)
    hash.compact
  end

  def numeric_value(value)
    return value if value.is_a?(Numeric)
    return value.to_i if value.to_s.match?(/\A-?\d+\z/)
    return value.to_f if value.to_s.match?(/\A-?\d+\.\d+\z/)

    nil
  end
end
