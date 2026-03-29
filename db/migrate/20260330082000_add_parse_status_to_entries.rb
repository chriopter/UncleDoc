class AddParseStatusToEntries < ActiveRecord::Migration[8.1]
  class MigrationEntry < ApplicationRecord
    self.table_name = "entries"
  end

  def up
    add_column :entries, :parse_status, :string, default: "parsed", null: false

    MigrationEntry.reset_column_information
    MigrationEntry.where(data: [ nil, [] ]).update_all(parse_status: "pending")
  end

  def down
    remove_column :entries, :parse_status, :string
  end
end
