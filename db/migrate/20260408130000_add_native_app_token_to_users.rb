class AddNativeAppTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :native_app_token, :text
    add_column :users, :native_app_token_digest, :string
    add_column :users, :native_app_token_generated_at, :datetime
    add_column :users, :native_app_token_last_used_at, :datetime

    add_index :users, :native_app_token_digest, unique: true
  end
end
