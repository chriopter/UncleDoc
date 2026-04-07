demo_now = Time.zone.now.change(sec: 0)

def upsert_entry(person:, occurred_at:, input:, facts:, parseable_data:, parse_status: nil, todo_done: false, todo_done_at: nil)
  entry = person.entries.find_or_initialize_by(occurred_at: occurred_at, input: input)
  entry.facts = facts
  entry.parseable_data = parseable_data
  entry.parse_status = parse_status if parse_status.present?
  entry.todo_done = todo_done if entry.has_attribute?(:todo_done)
  entry.todo_done_at = todo_done_at if entry.has_attribute?(:todo_done_at)
  entry.save!
end

def create_general_timeline(person, now:)
  90.times do |day_offset|
    day = now - day_offset.days

    weight = (31.5 - day_offset * 0.03).round(1)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 8, min: 15),
      input: "Weight check #{weight}kg",
      facts: [ "Weight #{weight} kg" ],
      parseable_data: [ { "type" => "weight", "value" => weight, "unit" => "kg" } ],
      parse_status: "parsed"
    ) if day_offset % 6 == 0

    height = (96 - day_offset * 0.05).round(1)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 9, min: 10),
      input: "Height check #{height}cm",
      facts: [ "Height #{height} cm" ],
      parseable_data: [ { "type" => "height", "value" => height, "unit" => "cm" } ],
      parse_status: "parsed"
    ) if day_offset % 15 == 0

    temp = (36.7 + ((day_offset % 5) * 0.1)).round(1)
    pulse = 78 + (day_offset % 16)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 12, min: 20),
      input: "Temperature #{temp}C and pulse #{pulse} bpm",
      facts: [ "Temperature #{temp} C", "Pulse #{pulse} bpm" ],
      parseable_data: [
        { "type" => "temperature", "value" => temp, "unit" => "C" },
        { "type" => "pulse", "value" => pulse, "unit" => "bpm" }
      ],
      parse_status: "parsed"
    )

    systolic = 116 + (day_offset % 8)
    diastolic = 74 + (day_offset % 6)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 18, min: 45),
      input: "Blood pressure #{systolic}/#{diastolic} after school",
      facts: [ "Blood pressure #{systolic}/#{diastolic} mmHg" ],
      parseable_data: [ { "type" => "blood_pressure", "systolic" => systolic, "diastolic" => diastolic, "unit" => "mmHg" } ],
      parse_status: "parsed"
    ) if day_offset % 2 == 0

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 20, min: 5),
      input: "Long free-form note about appetite, energy, mood, medication response, school pickup, hydration, and bedtime routine on #{day.to_date}.",
      facts: [ "Mood steady", "Ate well", "Hydration okay" ],
      parseable_data: [],
      parse_status: "skipped"
    )
  end

  12.times do |index|
    scheduled_at = now.beginning_of_day + (index + 2).days + 10.hours
    upsert_entry(
      person: person,
      occurred_at: scheduled_at,
      input: "Doctor appointment #{index + 1}",
      facts: [ "Doctor appointment #{index + 1}" ],
      parseable_data: [ { "type" => "appointment", "value" => "Doctor appointment #{index + 1}", "location" => [ "Pediatric clinic", "Pharmacy", "Orthopedics" ][index % 3], "scheduled_for" => scheduled_at.iso8601 } ],
      parse_status: "parsed"
    )
  end

  18.times do |index|
    due_at = (now.beginning_of_day + index.days + 18.hours).iso8601
    done = index % 4 == 0
    upsert_entry(
      person: person,
      occurred_at: now.beginning_of_day - index.days + 17.hours,
      input: "Todo #{index + 1}: prepare records and supplies",
      facts: [ "Prepare records and supplies #{index + 1}" ],
      parseable_data: [ { "type" => "todo", "value" => "Prepare records and supplies #{index + 1}", "due_at" => due_at } ],
      parse_status: "parsed",
      todo_done: done,
      todo_done_at: (done ? now.beginning_of_day - index.days + 19.hours : nil)
    )
  end

  [
    {
      occurred_at: now.change(hour: 7, min: 40),
      input: "Morning check before school: temperature 36.8C, pulse 76 bpm",
      facts: [ "Temperature 36.8 C", "Pulse 76 bpm", "Feeling energetic" ],
      parseable_data: [
        { "type" => "temperature", "value" => 36.8, "unit" => "C" },
        { "type" => "pulse", "value" => 76, "unit" => "bpm" }
      ]
    },
    {
      occurred_at: now.change(hour: 13, min: 5),
      input: "After lunch medication: ibuprofen 200mg for headache",
      facts: [ "Ibuprofen 200 mg", "Headache improved after lunch" ],
      parseable_data: [
        { "type" => "medication", "value" => "ibuprofen", "dose" => "200mg" }
      ]
    },
    {
      occurred_at: now.change(hour: 19, min: 10),
      input: "Evening blood pressure 118/76 after a long walk",
      facts: [ "Blood pressure 118/76 mmHg", "Walked in the park for 40 minutes" ],
      parseable_data: [
        { "type" => "blood_pressure", "systolic" => 118, "diastolic" => 76, "unit" => "mmHg" }
      ]
    }
  ].each do |entry_attrs|
    upsert_entry(
      person: person,
      occurred_at: entry_attrs[:occurred_at],
      input: entry_attrs[:input],
      facts: entry_attrs[:facts],
      parseable_data: entry_attrs[:parseable_data],
      parse_status: "parsed"
    )
  end
end

def create_baby_timeline(person, now:)
  45.times do |day_offset|
    day = now - day_offset.days

    3.times do |feeding_index|
      occurred_at = day.change(hour: 6 + (feeding_index * 5), min: [ 10, 25, 40 ][feeding_index])
      minutes = 12 + ((day_offset + feeding_index) % 14)
      side = feeding_index.even? ? "left" : "right"

      upsert_entry(
        person: person,
        occurred_at: occurred_at,
        input: "Breastfeeding #{side} #{minutes} min",
        facts: [ "Breast feeding #{side} #{minutes} min" ],
        parseable_data: [ { "type" => "breast_feeding", "value" => minutes, "unit" => "min", "side" => side } ],
        parse_status: "parsed"
      )
    end

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 14, min: 15),
      input: "Bottle feeding #{90 + ((day_offset * 5) % 40)} ml",
      facts: [ "Bottle feeding #{90 + ((day_offset * 5) % 40)} ml" ],
      parseable_data: [ { "type" => "bottle_feeding", "value" => 90 + ((day_offset * 5) % 40), "unit" => "ml" } ],
      parse_status: "parsed"
    )

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 11, min: 5),
      input: "Sleep #{70 + ((day_offset * 7) % 75)} min",
      facts: [ "Sleep #{70 + ((day_offset * 7) % 75)} min" ],
      parseable_data: [ { "type" => "sleep", "value" => 70 + ((day_offset * 7) % 75), "unit" => "min" } ],
      parse_status: "parsed"
    )

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 16, min: 45),
      input: "Diaper wet=#{day_offset.even?} solid=#{day_offset % 3 == 0}",
      facts: [ "Diaper #{day_offset.even? ? 'wet' : 'dry'}#{day_offset % 3 == 0 ? ' and solid' : ''}" ],
      parseable_data: [ { "type" => "diaper", "wet" => day_offset.even?, "solid" => day_offset % 3 == 0, "rash" => day_offset % 12 == 0 } ],
      parse_status: "parsed"
    )

    weight = (7.1 - day_offset * 0.02).round(2)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 9, min: 0),
      input: "Weight #{weight} kg",
      facts: [ "Weight #{weight} kg" ],
      parseable_data: [ { "type" => "weight", "value" => weight, "unit" => "kg" } ],
      parse_status: "parsed"
    ) if day_offset % 5 == 0

    height = (62.0 - day_offset * 0.04).round(1)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 9, min: 30),
      input: "Height #{height} cm",
      facts: [ "Height #{height} cm" ],
      parseable_data: [ { "type" => "height", "value" => height, "unit" => "cm" } ],
      parse_status: "parsed"
    ) if day_offset % 10 == 0

    temp = (36.5 + ((day_offset % 7) * 0.15)).round(1)
    pulse = 115 + ((day_offset * 7) % 15)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 10, min: 0),
      input: "Temperature #{temp}C, pulse #{pulse} bpm",
      facts: [ "Temperature #{temp} C", "Pulse #{pulse} bpm" ],
      parseable_data: [
        { "type" => "temperature", "value" => temp, "unit" => "C" },
        { "type" => "pulse", "value" => pulse, "unit" => "bpm" }
      ],
      parse_status: "parsed"
    )

    systolic = 80 + ((day_offset * 3) % 10)
    diastolic = 50 + ((day_offset * 5) % 8)
    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 17, min: 30),
      input: "Blood pressure #{systolic}/#{diastolic}",
      facts: [ "Blood pressure #{systolic}/#{diastolic} mmHg" ],
      parseable_data: [ { "type" => "blood_pressure", "systolic" => systolic, "diastolic" => diastolic, "unit" => "mmHg" } ],
      parse_status: "parsed"
    ) if day_offset % 3 == 0
  end

  8.times do |index|
    scheduled_at = now.beginning_of_day + (index + 2).days + 10.hours
    upsert_entry(
      person: person,
      occurred_at: scheduled_at,
      input: "Appointment #{index + 1}",
      facts: [ "Appointment #{index + 1}" ],
      parseable_data: [ { "type" => "appointment", "value" => "Appointment #{index + 1}", "location" => [ "Pediatrician", "Vaccination clinic", "Children's hospital" ][index % 3], "scheduled_for" => scheduled_at.iso8601 } ],
      parse_status: "parsed"
    )
  end

  10.times do |index|
    due_at = (now.beginning_of_day + index.days + 18.hours).iso8601
    done = index % 3 == 0
    upsert_entry(
      person: person,
      occurred_at: now.beginning_of_day - index.days + 17.hours,
      input: "Todo #{index + 1}: #{[ 'Buy diapers', 'Schedule vaccination', 'Prepare formula', 'Wash baby clothes', 'Book pediatrician' ][index % 5]}",
      facts: [ "#{[ 'Buy diapers', 'Schedule vaccination', 'Prepare formula', 'Wash baby clothes', 'Book pediatrician' ][index % 5]} #{index + 1}" ],
      parseable_data: [ { "type" => "todo", "value" => "#{[ 'Buy diapers', 'Schedule vaccination', 'Prepare formula', 'Wash baby clothes', 'Book pediatrician' ][index % 5]} #{index + 1}", "due_at" => due_at } ],
      parse_status: "parsed",
      todo_done: done,
      todo_done_at: (done ? now.beginning_of_day - index.days + 19.hours : nil)
    )
  end
end

legacy_demo_names = {
  "Demo Lina" => "Demo Nora"
}

legacy_demo_names.each do |old_name, new_name|
  person = Person.find_by(name: old_name)
  next unless person
  next if Person.exists?(name: new_name)

  person.update!(name: new_name)
end

people = [
  { name: "Demo Nora", birth_date: 6.years.ago, baby_mode: false, timeline: :general },
  { name: "Demo Theo", birth_date: 34.years.ago, baby_mode: false, timeline: :general },
  { name: "Demo Mila", birth_date: 6.months.ago, baby_mode: true, timeline: :baby }
]

people.each do |attrs|
  person = Person.find_or_initialize_by(name: attrs[:name])
  person.birth_date = attrs[:birth_date]
  person.baby_mode = attrs[:baby_mode]
  person.save!
  person.entries.destroy_all

  case attrs[:timeline]
  when :baby
    create_baby_timeline(person, now: demo_now)
  else
    create_general_timeline(person, now: demo_now)
  end
end

puts "Demo data ready: #{people.map { |person| person[:name] }.join(', ')}"
