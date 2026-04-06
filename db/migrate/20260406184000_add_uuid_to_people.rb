class AddUuidToPeople < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :uuid, :string
    add_index :people, :uuid, unique: true

    reversible do |dir|
      dir.up do
        say_with_time "Backfilling people UUIDs" do
          Person.reset_column_information
          Person.find_each do |person|
            person.update_columns(uuid: SecureRandom.uuid) if person.uuid.blank?
          end
        end
      end
    end
  end

  class Person < ApplicationRecord
    self.table_name = "people"
  end
end
