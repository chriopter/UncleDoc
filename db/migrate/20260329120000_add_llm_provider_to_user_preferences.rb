class AddLlmProviderToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :llm_provider, :string
  end
end
