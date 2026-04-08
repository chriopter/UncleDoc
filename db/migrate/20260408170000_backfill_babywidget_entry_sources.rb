class BackfillBabywidgetEntrySources < ActiveRecord::Migration[8.1]
  class MigrationEntry < ApplicationRecord
    self.table_name = "entries"
  end

  MANUAL_SOURCE = "manual".freeze
  BABYWIDGET_SOURCE = "babywidget".freeze
  INPUT_PATTERNS = [
    /\ADiaper: wet\z/,
    /\ADiaper: solid\z/,
    /\ADiaper: wet and solid\z/,
    /\AWindel: nass\z/,
    /\AWindel: fest\z/,
    /\AWindel: nass und fest\z/,
    /\ABottle \d+ml\z/,
    /\AFlasche \d+ml\z/,
    /\ABreastfeeding (?:Left|Right), \d+ minutes\z/,
    /\AStillen (?:Links|Rechts), \d+ Minuten\z/,
    /\ASleep \d+ min\z/,
    /\ASchlaf \d+ Min\z/
  ].freeze

  def up
    MigrationEntry.reset_column_information

    say_with_time "Backfilling baby widget entry sources" do
      updated_count = 0

      MigrationEntry.where(source: MANUAL_SOURCE).find_each do |entry|
        next unless babywidget_input?(entry.input)

        entry.update_columns(source: BABYWIDGET_SOURCE)
        updated_count += 1
      end

      updated_count
    end
  end

  def down
    MigrationEntry.where(source: BABYWIDGET_SOURCE).find_each do |entry|
      next unless babywidget_input?(entry.input)

      entry.update_columns(source: MANUAL_SOURCE)
    end
  end

  private

  def babywidget_input?(input)
    normalized_input = input.to_s.strip
    INPUT_PATTERNS.any? { |pattern| pattern.match?(normalized_input) }
  end
end
