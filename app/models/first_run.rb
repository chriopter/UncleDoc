class FirstRun
  def self.create!(person_name:, birth_date:, email_address:, password:, password_confirmation:)
    Person.transaction do
      person = Person.create!(name: person_name, birth_date: birth_date.presence)
      User.create!(
        person: person,
        email_address: email_address,
        password: password,
        password_confirmation: password_confirmation,
        admin: true
      )
    end
  end
end
