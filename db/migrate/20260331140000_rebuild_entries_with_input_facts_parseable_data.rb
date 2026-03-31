class RebuildEntriesWithInputFactsParseableData < ActiveRecord::Migration[8.1]
  def up
    connection.disable_referential_integrity do
      create_table :entries_rebuilt do |t|
        t.text :input, null: false
        t.json :facts, default: [], null: false
        t.json :parseable_data, default: [], null: false
        t.datetime :occurred_at, null: false
        t.string :parse_status, default: "parsed", null: false
        t.references :person, null: false, foreign_key: true
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end

      execute <<~SQL
        INSERT INTO entries_rebuilt (id, input, facts, parseable_data, occurred_at, parse_status, person_id, created_at, updated_at)
        SELECT id, note, fact_list, data, occurred_at, parse_status, person_id, created_at, updated_at
        FROM entries
      SQL

      drop_table :entries
      rename_table :entries_rebuilt, :entries
    end
  end

  def down
    connection.disable_referential_integrity do
      create_table :entries_legacy do |t|
        t.text :note, null: false
        t.json :fact_list, default: [], null: false
        t.json :data, default: [], null: false
        t.datetime :occurred_at, null: false
        t.string :parse_status, default: "parsed", null: false
        t.references :person, null: false, foreign_key: true
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end

      execute <<~SQL
        INSERT INTO entries_legacy (id, note, fact_list, data, occurred_at, parse_status, person_id, created_at, updated_at)
        SELECT id, input, facts, parseable_data, occurred_at, parse_status, person_id, created_at, updated_at
        FROM entries
      SQL

      drop_table :entries
      rename_table :entries_legacy, :entries
    end
  end
end
