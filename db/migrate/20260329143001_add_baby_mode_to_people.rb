class AddBabyModeToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :baby_mode, :boolean
  end
end
