class BackfillPeopleUuidAndEnforceNotNull < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    with_people_fk_suspended do
      say_with_time "Backfilling missing people UUIDs" do
        Person.reset_column_information
        Person.where(uuid: [ nil, "" ]).find_each do |person|
          person.update_columns(uuid: SecureRandom.uuid)
        end
      end

      add_index :people, :uuid, unique: true unless index_exists?(:people, :uuid)
      change_column_null :people, :uuid, false
    end
  end

  def down
    with_people_fk_suspended do
      change_column_null :people, :uuid, true
    end
  end

  private

  def with_people_fk_suspended
    if sqlite?
      execute "PRAGMA foreign_keys = OFF"
      yield
    else
      connection.disable_referential_integrity { yield }
    end
  ensure
    execute "PRAGMA foreign_keys = ON" if sqlite?
  end

  def sqlite?
    connection.adapter_name.casecmp("SQLite").zero?
  end

  class Person < ApplicationRecord
    self.table_name = "people"
  end
end
