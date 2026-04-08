class CreateUserDevices < ActiveRecord::Migration[8.1]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  class MigrationUserDevice < ApplicationRecord
    self.table_name = "user_devices"

    encrypts :token
  end

  IOS_PLATFORM = "ios".freeze
  DEFAULT_NAME = "UncleDoc iOS".freeze

  def up
    create_table :user_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :platform, null: false
      t.text :token
      t.string :token_digest
      t.datetime :token_generated_at
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :user_devices, :token_digest, unique: true

    MigrationUser.reset_column_information
    MigrationUserDevice.reset_column_information

    return unless MigrationUser.column_names.include?("native_app_token_digest")

    MigrationUser.where.not(native_app_token_digest: [ nil, "" ]).find_each do |user|
      MigrationUserDevice.create!(
        user_id: user.id,
        name: DEFAULT_NAME,
        platform: IOS_PLATFORM,
        token: user.respond_to?(:native_app_token) ? user.native_app_token : nil,
        token_digest: user.native_app_token_digest,
        token_generated_at: user.try(:native_app_token_generated_at),
        last_used_at: user.try(:native_app_token_last_used_at)
      )
    end
  end

  def down
    drop_table :user_devices
  end
end
