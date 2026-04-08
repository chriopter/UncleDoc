class RemoveLocaleAndDateFormatFromPeople < ActiveRecord::Migration[8.1]
  def change
    remove_column :people, :locale, :string
    remove_column :people, :date_format, :string
  end
end
