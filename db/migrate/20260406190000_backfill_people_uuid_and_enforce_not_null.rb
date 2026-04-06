class BackfillPeopleUuidAndEnforceNotNull < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Backfilling missing people UUIDs" do
      Person.reset_column_information
      Person.where(uuid: [ nil, "" ]).find_each do |person|
        person.update_columns(uuid: SecureRandom.uuid)
      end
    end

    add_index :people, :uuid, unique: true unless index_exists?(:people, :uuid)
    change_column_null :people, :uuid, false
  end

  def down
    change_column_null :people, :uuid, true
  end

  class Person < ApplicationRecord
    self.table_name = "people"
  end
end
