class AddDisplayPreferencesToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :locale, :string
    add_column :people, :date_format, :string
  end
end
