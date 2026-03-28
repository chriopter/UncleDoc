class CreateUserPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :user_preferences do |t|
      t.string :locale
      t.string :date_format

      t.timestamps
    end
  end
end
