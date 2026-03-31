class AddTodoStateToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :todo_done, :boolean, default: false, null: false
    add_column :entries, :todo_done_at, :datetime
  end
end
