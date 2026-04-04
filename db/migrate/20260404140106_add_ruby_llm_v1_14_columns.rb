class AddRubyLlmV114Columns < ActiveRecord::Migration[8.1]
  def change
    if table_exists?(:tool_calls) && column_exists?(:tool_calls, :thought_signature, :string)
      change_column :tool_calls, :thought_signature, :text
    end
  end
end
