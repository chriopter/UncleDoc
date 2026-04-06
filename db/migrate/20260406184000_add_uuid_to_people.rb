class AddUuidToPeople < ActiveRecord::Migration[8.0]
  def up
    add_column :people, :uuid, :string

    say_with_time "Backfilling people UUIDs" do
      Person.reset_column_information
      Person.find_each do |person|
        person.update_columns(uuid: SecureRandom.uuid) if person.uuid.blank?
      end
    end

    change_column_null :people, :uuid, false
    add_index :people, :uuid, unique: true
  end

  def down
    remove_index :people, :uuid
    remove_column :people, :uuid
  end

  class Person < ApplicationRecord
    self.table_name = "people"
  end
end
