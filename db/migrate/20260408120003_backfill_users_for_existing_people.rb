class BackfillUsersForExistingPeople < ActiveRecord::Migration[8.1]
  class MigrationPerson < ApplicationRecord
    self.table_name = "people"
  end

  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    MigrationPerson.find_each.with_index do |person, index|
      next if MigrationUser.exists?(person_id: person.id)

      MigrationUser.create!(
        person_id: person.id,
        email_address: generated_email_for(person),
        admin: index.zero?
      )
    end
  end

  def down
    MigrationUser.where("email_address LIKE ?", "person-%@uncledoc.invalid").delete_all
  end

  private

  def generated_email_for(person)
    "person-#{person.id}@uncledoc.invalid"
  end
end
