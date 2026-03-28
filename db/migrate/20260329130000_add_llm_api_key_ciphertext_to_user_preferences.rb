class AddLlmApiKeyCiphertextToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :llm_api_key_ciphertext, :text
  end
end
