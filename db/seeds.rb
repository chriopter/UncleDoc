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

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 8, min: 15),
      input: "Weight check #{(31.5 + day_offset * 0.03).round(1)}kg",
      facts: [ "Weight #{(31.5 + day_offset * 0.03).round(1)} kg" ],
      parseable_data: [ { "type" => "weight", "value" => (31.5 + day_offset * 0.03).round(1), "unit" => "kg" } ],
      parse_status: "parsed"
    ) if day_offset % 6 == 0

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 9, min: 10),
      input: "Height check #{(96 + day_offset * 0.05).round(1)}cm",
      facts: [ "Height #{(96 + day_offset * 0.05).round(1)} cm" ],
      parseable_data: [ { "type" => "height", "value" => (96 + day_offset * 0.05).round(1), "unit" => "cm" } ],
      parse_status: "parsed"
    ) if day_offset % 15 == 0

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 12, min: 20),
      input: "Temperature #{(36.7 + ((day_offset % 5) * 0.1)).round(1)}C and pulse #{78 + (day_offset % 16)} bpm",
      facts: [ "Temperature #{(36.7 + ((day_offset % 5) * 0.1)).round(1)} C", "Pulse #{78 + (day_offset % 16)} bpm" ],
      parseable_data: [
        { "type" => "temperature", "value" => (36.7 + ((day_offset % 5) * 0.1)).round(1), "unit" => "C" },
        { "type" => "pulse", "value" => 78 + (day_offset % 16), "unit" => "bpm" }
      ],
      parse_status: "parsed"
    )

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 18, min: 45),
      input: "Blood pressure #{116 + (day_offset % 8)}/#{74 + (day_offset % 6)} after school",
      facts: [ "Blood pressure #{116 + (day_offset % 8)}/#{74 + (day_offset % 6)} mmHg" ],
      parseable_data: [ { "type" => "blood_pressure", "systolic" => 116 + (day_offset % 8), "diastolic" => 74 + (day_offset % 6), "unit" => "mmHg" } ],
      parse_status: "parsed"
    ) if day_offset % 2 == 0

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 20, min: 5),
      input: "Long free-form note about appetite, energy, mood, medication response, school pickup, hydration, and bedtime routine on #{day.to_date}.",
      facts: [ "Mood steady", "Ate well", "Hydration okay" ],
      parseable_data: [],
      parse_status: day_offset % 11 == 0 ? "failed" : "skipped"
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

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 9, min: 0),
      input: "Weight #{(4.2 + day_offset * 0.02).round(2)} kg",
      facts: [ "Weight #{(4.2 + day_offset * 0.02).round(2)} kg" ],
      parseable_data: [ { "type" => "weight", "value" => (4.2 + day_offset * 0.02).round(2), "unit" => "kg" } ],
      parse_status: "parsed"
    ) if day_offset % 5 == 0

    upsert_entry(
      person: person,
      occurred_at: day.change(hour: 9, min: 30),
      input: "Height #{(54 + day_offset * 0.04).round(1)} cm",
      facts: [ "Height #{(54 + day_offset * 0.04).round(1)} cm" ],
      parseable_data: [ { "type" => "height", "value" => (54 + day_offset * 0.04).round(1), "unit" => "cm" } ],
      parse_status: "parsed"
    ) if day_offset % 10 == 0
  end
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

  case attrs[:timeline]
  when :baby
    create_baby_timeline(person, now: demo_now)
  else
    create_general_timeline(person, now: demo_now)
  end
end

puts "Demo data ready: #{people.map { |person| person[:name] }.join(', ')}"
