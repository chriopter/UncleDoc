class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest
      t.references :person, null: false, foreign_key: true, index: { unique: true }
      t.boolean :admin, null: false, default: false
      t.datetime :password_set_at
      t.datetime :last_signed_in_at

      t.timestamps
    end

    add_index :users, :email_address, unique: true
  end
end
