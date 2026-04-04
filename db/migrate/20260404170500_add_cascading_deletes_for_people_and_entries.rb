class AddCascadingDeletesForPeopleAndEntries < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :llm_logs, :entries
    remove_foreign_key :llm_logs, :people
    remove_foreign_key :entries, :people

    add_foreign_key :entries, :people, on_delete: :cascade
    add_foreign_key :llm_logs, :entries, on_delete: :cascade
    add_foreign_key :llm_logs, :people, on_delete: :cascade
  end

  def down
    remove_foreign_key :llm_logs, :entries
    remove_foreign_key :llm_logs, :people
    remove_foreign_key :entries, :people

    add_foreign_key :entries, :people
    add_foreign_key :llm_logs, :entries
    add_foreign_key :llm_logs, :people
  end
end
