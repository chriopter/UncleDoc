require "json"
require "set"

class HealthkitSummaryPreviewer
  Preview = Struct.new(
    :source_ref,
    :period_type,
    :starts_on,
    :ends_on,
    :occurred_at,
    :input,
    :present_record_types,
    :mentioned_record_types,
    :missing_record_types,
    :record_count,
    keyword_init: true
  )

  RECORD_TYPE_LABELS = {
    "HKQuantityTypeIdentifierActiveEnergyBurned" => "Active energy burned",
    "HKQuantityTypeIdentifierBasalEnergyBurned" => "Basal energy burned",
    "HKQuantityTypeIdentifierDistanceWalkingRunning" => "Walking and running distance",
    "HKQuantityTypeIdentifierDistanceCycling" => "Cycling distance",
    "HKQuantityTypeIdentifierStepCount" => "Step count",
    "HKQuantityTypeIdentifierWalkingStepLength" => "Walking step length",
    "HKQuantityTypeIdentifierWalkingSpeed" => "Walking speed",
    "HKQuantityTypeIdentifierHeartRate" => "Heart rate",
    "HKQuantityTypeIdentifierRestingHeartRate" => "Resting heart rate",
    "HKQuantityTypeIdentifierWalkingHeartRateAverage" => "Walking heart rate average",
    "HKQuantityTypeIdentifierHeartRateVariabilitySDNN" => "Heart rate variability",
    "HKQuantityTypeIdentifierRespiratoryRate" => "Respiratory rate",
    "HKQuantityTypeIdentifierOxygenSaturation" => "Oxygen saturation",
    "HKQuantityTypeIdentifierVO2Max" => "VO2 max",
    "HKQuantityTypeIdentifierFlightsClimbed" => "Flights climbed",
    "HKQuantityTypeIdentifierDietaryEnergyConsumed" => "Dietary energy consumed",
    "HKQuantityTypeIdentifierDietaryCarbohydrates" => "Dietary carbohydrates",
    "HKQuantityTypeIdentifierDietaryProtein" => "Dietary protein",
    "HKQuantityTypeIdentifierDietaryFatTotal" => "Dietary fat",
    "HKQuantityTypeIdentifierDietarySugar" => "Dietary sugar",
    "HKQuantityTypeIdentifierDietaryWater" => "Dietary water",
    "HKQuantityTypeIdentifierBloodPressureSystolic" => "Blood pressure systolic",
    "HKQuantityTypeIdentifierBloodPressureDiastolic" => "Blood pressure diastolic",
    "HKQuantityTypeIdentifierBodyMass" => "Weight",
    "HKQuantityTypeIdentifierBodyMassIndex" => "Body mass index",
    "HKQuantityTypeIdentifierBodyFatPercentage" => "Body fat percentage",
    "HKQuantityTypeIdentifierHeight" => "Height",
    "HKQuantityTypeIdentifierBodyTemperature" => "Body temperature",
    "HKCategoryTypeIdentifierAppleStandHour" => "Apple stand hour",
    "HKCategoryTypeIdentifierSleepAnalysis" => "Sleep analysis",
    "HKCategoryTypeIdentifierAudioExposureEvent" => "Audio exposure event",
    "HKWorkoutTypeIdentifier" => "Workout",
    "HKDataTypeIdentifierElectrocardiogram" => "Electrocardiogram",
    "HKDataTypeIdentifierAudiogram" => "Audiogram",
    "HKDataTypeStateOfMind" => "State of mind",
    "characteristic.activityMoveMode" => "Activity move mode",
    "characteristic.biologicalSex" => "Biological sex",
    "characteristic.bloodType" => "Blood type",
    "characteristic.dateOfBirth" => "Date of birth",
    "characteristic.fitzpatrickSkinType" => "Fitzpatrick skin type",
    "characteristic.wheelchairUse" => "Wheelchair use"
  }.freeze

  MOVEMENT_TYPES = %w[
    HKQuantityTypeIdentifierStepCount
    HKQuantityTypeIdentifierDistanceWalkingRunning
    HKQuantityTypeIdentifierDistanceCycling
    HKQuantityTypeIdentifierActiveEnergyBurned
    HKQuantityTypeIdentifierBasalEnergyBurned
    HKQuantityTypeIdentifierFlightsClimbed
    HKQuantityTypeIdentifierWalkingSpeed
    HKQuantityTypeIdentifierWalkingStepLength
    HKCategoryTypeIdentifierAppleStandHour
  ].freeze

  CARDIO_TYPES = %w[
    HKQuantityTypeIdentifierHeartRate
    HKQuantityTypeIdentifierRestingHeartRate
    HKQuantityTypeIdentifierWalkingHeartRateAverage
    HKQuantityTypeIdentifierHeartRateVariabilitySDNN
    HKQuantityTypeIdentifierRespiratoryRate
    HKQuantityTypeIdentifierOxygenSaturation
    HKQuantityTypeIdentifierVO2Max
    HKQuantityTypeIdentifierBloodPressureSystolic
    HKQuantityTypeIdentifierBloodPressureDiastolic
  ].freeze

  NUTRITION_TYPES = %w[
    HKQuantityTypeIdentifierDietaryEnergyConsumed
    HKQuantityTypeIdentifierDietaryCarbohydrates
    HKQuantityTypeIdentifierDietaryProtein
    HKQuantityTypeIdentifierDietaryFatTotal
    HKQuantityTypeIdentifierDietarySugar
    HKQuantityTypeIdentifierDietaryWater
  ].freeze

  BODY_TYPES = %w[
    HKQuantityTypeIdentifierBodyMass
    HKQuantityTypeIdentifierBodyMassIndex
    HKQuantityTypeIdentifierBodyFatPercentage
    HKQuantityTypeIdentifierHeight
    HKQuantityTypeIdentifierBodyTemperature
  ].freeze

  ASSESSMENT_TYPES = %w[
    HKDataTypeIdentifierElectrocardiogram
    HKDataTypeIdentifierAudiogram
    HKDataTypeStateOfMind
  ].freeze

  CHARACTERISTIC_TYPES = %w[
    characteristic.activityMoveMode
    characteristic.biologicalSex
    characteristic.bloodType
    characteristic.dateOfBirth
    characteristic.fitzpatrickSkinType
    characteristic.wheelchairUse
  ].freeze

  def self.call(person:, today: Time.zone.today)
    new(person:, today:).call
  end

  def initialize(person:, today: Time.zone.today)
    @person = person
    @today = today.to_date
  end

  def call
    first_record_at = @person.healthkit_records.minimum(:start_at)
    return [] unless first_record_at

    first_date = first_record_at.in_time_zone.to_date
    last_closed_day = @today - 1.day
    return [] if last_closed_day < first_date

    daily_aggregates = build_daily_aggregates(first_date:, last_closed_day:)
    daily_previews = daily_aggregates.map do |date, aggregate|
      build_preview(period_type: :day, starts_on: date, ends_on: date, aggregate:)
    end

    previous_month_start = @today.prev_month.beginning_of_month

    exposed_daily_previews = daily_previews.select { |preview| preview.starts_on >= previous_month_start }

    monthly_previews = daily_aggregates
      .select { |date, _aggregate| date < previous_month_start }
      .group_by { |date, _aggregate| date.beginning_of_month }
      .map do |month_start, aggregates|
        month_end = month_start.end_of_month
        month_aggregate = aggregates.map(&:last).reduce(blank_aggregate(days_count: 0)) do |memo, aggregate|
          merge_aggregates(memo, aggregate)
        end

        build_preview(period_type: :month, starts_on: month_start, ends_on: month_end, aggregate: month_aggregate)
      end

    (monthly_previews + exposed_daily_previews).sort_by(&:starts_on)
  end

  private

  def build_daily_aggregates(first_date:, last_closed_day:)
    aggregates = (first_date..last_closed_day).index_with { blank_aggregate(days_count: 1) }

    @person.healthkit_records.in_batches(of: 1000) do |batch|
      batch.pluck(:record_type, :source_name, :start_at, :end_at, :payload).each do |record_type, source_name, start_at, end_at, payload|
        next unless start_at

        date = start_at.in_time_zone.to_date
        next if date < first_date || date > last_closed_day

        aggregate = aggregates.fetch(date)
        update_aggregate(aggregate, record_type:, source_name:, start_at:, end_at:, payload:)
      end
    end

    aggregates.each_value do |aggregate|
      aggregate[:days_with_data] = aggregate[:record_count].positive? ? 1 : 0
    end

    aggregates
  end

  def build_preview(period_type:, starts_on:, ends_on:, aggregate:)
    if aggregate[:record_count].zero?
      return Preview.new(
        source_ref: source_ref_for(period_type, starts_on),
        period_type: period_type,
        starts_on: starts_on,
        ends_on: ends_on,
        occurred_at: occurred_at_for(period_type, starts_on, ends_on),
        input: empty_input_for(period_type, starts_on),
        present_record_types: [],
        mentioned_record_types: [],
        missing_record_types: [],
        record_count: 0
      )
    end

    sections = []
    mentioned = Set.new
    present_types = aggregate[:types].keys.sort

    add_section(sections, mentioned, movement_section(aggregate))
    add_section(sections, mentioned, cardio_section(aggregate))
    add_section(sections, mentioned, sleep_section(aggregate))
    add_section(sections, mentioned, nutrition_section(aggregate))
    add_section(sections, mentioned, body_section(aggregate, period_type))
    add_section(sections, mentioned, workout_section(aggregate))
    add_section(sections, mentioned, assessment_section(aggregate))
    add_section(sections, mentioned, characteristic_section(aggregate))

    missing_types = present_types - mentioned.to_a
    if missing_types.any?
      sections << other_section(aggregate, missing_types)
      mentioned.merge(missing_types)
    end

    header = header_for(period_type, starts_on)
    coverage = coverage_sentence(period_type, aggregate)
    body = [ coverage, *sections ].compact

    Preview.new(
      source_ref: source_ref_for(period_type, starts_on),
      period_type: period_type,
      starts_on: starts_on,
      ends_on: ends_on,
      occurred_at: occurred_at_for(period_type, starts_on, ends_on),
      input: ([ header ] + body).join("\n\n"),
      present_record_types: present_types,
      mentioned_record_types: mentioned.to_a.sort,
      missing_record_types: present_types - mentioned.to_a,
      record_count: aggregate[:record_count]
    )
  end

  def blank_aggregate(days_count:)
    {
      record_count: 0,
      days_count: days_count,
      days_with_data: 0,
      source_names: Set.new,
      types: {}
    }
  end

  def blank_type_aggregate
    {
      count: 0,
      source_names: Set.new,
      first_at: nil,
      last_at: nil,
      quantity_sum: 0.0,
      quantity_count: 0,
      quantity_min: nil,
      quantity_max: nil,
      unit: nil,
      latest_quantity_value: nil,
      latest_quantity_unit: nil,
      latest_at: nil,
      duration_seconds: 0.0,
      values: Hash.new(0)
    }
  end

  def update_aggregate(aggregate, record_type:, source_name:, start_at:, end_at:, payload:)
    aggregate[:record_count] += 1
    aggregate[:source_names] << source_name if source_name.present?

    type_aggregate = aggregate[:types][record_type] ||= blank_type_aggregate
    type_aggregate[:count] += 1
    type_aggregate[:source_names] << source_name if source_name.present?
    type_aggregate[:first_at] = [ type_aggregate[:first_at], start_at ].compact.min
    type_aggregate[:last_at] = [ type_aggregate[:last_at], start_at ].compact.max

    quantity_value, quantity_unit = extract_quantity(payload)
    if quantity_value
      type_aggregate[:quantity_sum] += quantity_value
      type_aggregate[:quantity_count] += 1
      type_aggregate[:quantity_min] = [ type_aggregate[:quantity_min], quantity_value ].compact.min
      type_aggregate[:quantity_max] = [ type_aggregate[:quantity_max], quantity_value ].compact.max
      type_aggregate[:unit] ||= quantity_unit

      if type_aggregate[:latest_at].nil? || start_at >= type_aggregate[:latest_at]
        type_aggregate[:latest_at] = start_at
        type_aggregate[:latest_quantity_value] = quantity_value
        type_aggregate[:latest_quantity_unit] = quantity_unit
      end
    end

    type_aggregate[:duration_seconds] += [ end_at.to_f - start_at.to_f, 0 ].max if end_at.present?

    value = extract_value(payload)
    type_aggregate[:values][value] += 1 if value.present?
  end

  def merge_aggregates(left, right)
    merged = blank_aggregate(days_count: left[:days_count] + right[:days_count])
    merged[:record_count] = left[:record_count] + right[:record_count]
    merged[:days_with_data] = left[:days_with_data] + right[:days_with_data]
    merged[:source_names] = left[:source_names] | right[:source_names]

    (left[:types].keys | right[:types].keys).each do |record_type|
      merged[:types][record_type] = merge_type_aggregates(left[:types][record_type], right[:types][record_type])
    end

    merged
  end

  def merge_type_aggregates(left, right)
    left ||= blank_type_aggregate
    right ||= blank_type_aggregate

    values = Hash.new(0)
    left[:values].each { |key, count| values[key] += count }
    right[:values].each { |key, count| values[key] += count }

    latest_pair = [
      [ left[:latest_at], left[:latest_quantity_value], left[:latest_quantity_unit] ],
      [ right[:latest_at], right[:latest_quantity_value], right[:latest_quantity_unit] ]
    ].compact.max_by(&:first)

    {
      count: left[:count] + right[:count],
      source_names: left[:source_names] | right[:source_names],
      first_at: [ left[:first_at], right[:first_at] ].compact.min,
      last_at: [ left[:last_at], right[:last_at] ].compact.max,
      quantity_sum: left[:quantity_sum] + right[:quantity_sum],
      quantity_count: left[:quantity_count] + right[:quantity_count],
      quantity_min: [ left[:quantity_min], right[:quantity_min] ].compact.min,
      quantity_max: [ left[:quantity_max], right[:quantity_max] ].compact.max,
      unit: left[:unit] || right[:unit],
      latest_quantity_value: latest_pair&.[](1),
      latest_quantity_unit: latest_pair&.[](2),
      latest_at: latest_pair&.[](0),
      duration_seconds: left[:duration_seconds] + right[:duration_seconds],
      values: values
    }
  end

  def movement_section(aggregate)
    parts = []
    covered = []

    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierStepCount", unit: "count")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDistanceWalkingRunning", transform: 0.001, unit: "km")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDistanceCycling", transform: 0.001, unit: "km")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierActiveEnergyBurned", unit: "kcal")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierBasalEnergyBurned", unit: "kcal")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierFlightsClimbed", unit: "count")
    append_average_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierWalkingSpeed")
    append_average_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierWalkingStepLength")

    stand = aggregate[:types]["HKCategoryTypeIdentifierAppleStandHour"]
    if stand
      completed_hours = stand[:values]["1"]
      parts << "Apple stand hour #{completed_hours} completed hours across #{stand[:count]} records"
      covered << "HKCategoryTypeIdentifierAppleStandHour"
    end

    return if parts.empty?

    [ "Movement: #{parts.join('. ')}.", covered ]
  end

  def cardio_section(aggregate)
    parts = []
    covered = []

    append_avg_min_max(parts, covered, aggregate, "HKQuantityTypeIdentifierHeartRate")
    append_avg_min_max(parts, covered, aggregate, "HKQuantityTypeIdentifierRestingHeartRate")
    append_avg_min_max(parts, covered, aggregate, "HKQuantityTypeIdentifierWalkingHeartRateAverage")
    append_avg_min_max(parts, covered, aggregate, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
    append_avg_min_max(parts, covered, aggregate, "HKQuantityTypeIdentifierRespiratoryRate")
    append_avg_min_max(parts, covered, aggregate, "HKQuantityTypeIdentifierOxygenSaturation")
    append_avg_min_max(parts, covered, aggregate, "HKQuantityTypeIdentifierVO2Max")

    systolic = aggregate[:types]["HKQuantityTypeIdentifierBloodPressureSystolic"]
    diastolic = aggregate[:types]["HKQuantityTypeIdentifierBloodPressureDiastolic"]
    if systolic || diastolic
      pair = []
      pair << "systolic avg #{format_number(average_quantity(systolic))} #{display_unit(systolic, override: 'mmHg')}" if systolic&.dig(:quantity_count).to_i.positive?
      pair << "diastolic avg #{format_number(average_quantity(diastolic))} #{display_unit(diastolic, override: 'mmHg')}" if diastolic&.dig(:quantity_count).to_i.positive?
      parts << "Blood pressure #{pair.join(', ')}"
      covered.concat([ "HKQuantityTypeIdentifierBloodPressureSystolic", "HKQuantityTypeIdentifierBloodPressureDiastolic" ].select { |type| aggregate[:types][type] })
    end

    return if parts.empty?

    [ "Cardio and recovery: #{parts.join('. ')}.", covered ]
  end

  def sleep_section(aggregate)
    sleep = aggregate[:types]["HKCategoryTypeIdentifierSleepAnalysis"]
    return unless sleep

    hours = sleep[:duration_seconds] / 3600.0
    value_text = if sleep[:values].any?
      " Sleep category values: #{sleep[:values].sort_by { |value, _count| value.to_s }.map { |value, count| "#{value} (#{count})" }.join(', ')}."
    else
      ""
    end

    [ "Sleep: Sleep analysis #{format_number(hours)} hours across #{sleep[:count]} segments.#{value_text}".strip, [ "HKCategoryTypeIdentifierSleepAnalysis" ] ]
  end

  def nutrition_section(aggregate)
    parts = []
    covered = []

    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDietaryEnergyConsumed", unit: "kcal")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDietaryCarbohydrates")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDietaryProtein")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDietaryFatTotal")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDietarySugar")
    append_total_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierDietaryWater")

    return if parts.empty?

    [ "Nutrition: #{parts.join('. ')}.", covered ]
  end

  def body_section(aggregate, period_type)
    parts = []
    covered = []

    weight = aggregate[:types]["HKQuantityTypeIdentifierBodyMass"]
    if weight&.dig(:quantity_count).to_i.positive?
      parts << if period_type == :day
        "Weight #{format_number(weight[:latest_quantity_value])} #{display_unit(weight, override: 'kg')}"
      else
        "Weight avg #{format_number(average_quantity(weight))} #{display_unit(weight, override: 'kg')}, min #{format_number(weight[:quantity_min])}, max #{format_number(weight[:quantity_max])}"
      end
      covered << "HKQuantityTypeIdentifierBodyMass"
    end

    append_average_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierBodyMassIndex")
    append_average_quantity(parts, covered, aggregate, "HKQuantityTypeIdentifierBodyFatPercentage")

    height = aggregate[:types]["HKQuantityTypeIdentifierHeight"]
    if height&.dig(:quantity_count).to_i.positive?
      parts << "Height #{format_number(height[:latest_quantity_value])} #{display_unit(height)}"
      covered << "HKQuantityTypeIdentifierHeight"
    end

    temperature = aggregate[:types]["HKQuantityTypeIdentifierBodyTemperature"]
    if temperature&.dig(:quantity_count).to_i.positive?
      parts << if period_type == :day
        "Body temperature #{format_number(temperature[:latest_quantity_value])} #{display_unit(temperature, override: 'C')}"
      else
        "Body temperature avg #{format_number(average_quantity(temperature))} #{display_unit(temperature, override: 'C')}"
      end
      covered << "HKQuantityTypeIdentifierBodyTemperature"
    end

    return if parts.empty?

    [ "Body measurements: #{parts.join('. ')}.", covered ]
  end

  def workout_section(aggregate)
    parts = []
    covered = []

    workout = aggregate[:types]["HKWorkoutTypeIdentifier"]
    if workout
      parts << "Workouts #{workout[:count]} with #{format_number(workout[:duration_seconds] / 60.0)} total minutes"
      covered << "HKWorkoutTypeIdentifier"
    end

    audio = aggregate[:types]["HKCategoryTypeIdentifierAudioExposureEvent"]
    if audio
      parts << "Audio exposure events #{audio[:count]} with #{format_number(audio[:duration_seconds] / 60.0)} total minutes"
      covered << "HKCategoryTypeIdentifierAudioExposureEvent"
    end

    return if parts.empty?

    [ "Activities and events: #{parts.join('. ')}.", covered ]
  end

  def assessment_section(aggregate)
    parts = []
    covered = []

    ASSESSMENT_TYPES.each do |record_type|
      type_aggregate = aggregate[:types][record_type]
      next unless type_aggregate

      parts << "#{label_for(record_type)} #{type_aggregate[:count]} record#{'s' unless type_aggregate[:count] == 1}"
      covered << record_type
    end

    return if parts.empty?

    [ "Assessments: #{parts.join('. ')}.", covered ]
  end

  def characteristic_section(aggregate)
    present = CHARACTERISTIC_TYPES.select { |record_type| aggregate[:types][record_type] }
    return if present.empty?

    labels = present.map { |record_type| "#{label_for(record_type)} (#{record_type})" }
    [ "Health profile characteristics present: #{labels.join(', ')}.", present ]
  end

  def other_section(aggregate, record_types)
    details = record_types.map do |record_type|
      type_aggregate = aggregate[:types][record_type]
      "#{label_for(record_type)} (#{record_type}) #{type_aggregate[:count]} record#{'s' unless type_aggregate[:count] == 1}"
    end

    "Other HealthKit data: #{details.join('. ')}."
  end

  def append_total_quantity(parts, covered, aggregate, record_type, transform: 1.0, unit: nil)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    total = type_aggregate[:quantity_sum] * transform
    parts << "#{label_for(record_type)} #{format_number(total)} #{display_unit(type_aggregate, override: unit)}".strip
    covered << record_type
  end

  def append_average_quantity(parts, covered, aggregate, record_type, unit: nil)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    parts << "#{label_for(record_type)} avg #{format_number(average_quantity(type_aggregate))} #{display_unit(type_aggregate, override: unit)}".strip
    covered << record_type
  end

  def append_avg_min_max(parts, covered, aggregate, record_type)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    parts << "#{label_for(record_type)} avg #{format_number(average_quantity(type_aggregate))} #{display_unit(type_aggregate)}, min #{format_number(type_aggregate[:quantity_min])}, max #{format_number(type_aggregate[:quantity_max])}"
    covered << record_type
  end

  def add_section(sections, mentioned, section)
    return unless section

    text, record_types = section
    return if text.blank?

    sections << text
    mentioned.merge(record_types)
  end

  def average_quantity(type_aggregate)
    return 0 if type_aggregate[:quantity_count].zero?

    type_aggregate[:quantity_sum] / type_aggregate[:quantity_count]
  end

  def display_unit(type_aggregate, override: nil)
    return override if override.present?

    type_aggregate[:unit].to_s.strip
  end

  def extract_quantity(payload)
    quantity = normalize_payload(payload)["quantity"].to_s.strip
    return [ nil, nil ] if quantity.blank?

    match = quantity.match(/\A(-?\d+(?:\.\d+)?)\s*(.*)\z/)
    return [ nil, nil ] unless match

    [ match[1].to_f, match[2].presence ]
  end

  def extract_value(payload)
    normalize_payload(payload)["value"].to_s.strip.presence
  end

  def normalize_payload(payload)
    case payload
    when Hash
      payload.stringify_keys
    when String
      JSON.parse(payload)
    else
      payload.respond_to?(:to_h) ? payload.to_h.stringify_keys : {}
    end
  rescue JSON::ParserError, TypeError
    {}
  end

  def source_ref_for(period_type, starts_on)
    case period_type.to_sym
    when :month
      "healthkit:month:#{starts_on.strftime('%Y-%m')}"
    else
      "healthkit:day:#{starts_on.iso8601}"
    end
  end

  def occurred_at_for(period_type, starts_on, ends_on)
    case period_type.to_sym
    when :month
      ends_on.end_of_month.end_of_day
    else
      starts_on.end_of_day
    end
  end

  def header_for(period_type, starts_on)
    case period_type.to_sym
    when :month
      "HealthKit monthly summary for #{starts_on.strftime('%B %Y')}."
    else
      "HealthKit daily summary for #{starts_on.iso8601}."
    end
  end

  def coverage_sentence(period_type, aggregate)
    return if period_type.to_sym == :day

    "Coverage: #{aggregate[:days_count]} daily summaries, #{aggregate[:days_with_data]} days with HealthKit data, #{aggregate[:record_count]} raw records."
  end

  def empty_input_for(period_type, starts_on)
    case period_type.to_sym
    when :month
      "HealthKit monthly summary for #{starts_on.strftime('%B %Y')}. No HealthKit data was recorded for this month."
    else
      "HealthKit daily summary for #{starts_on.iso8601}. No HealthKit data was recorded for this day."
    end
  end

  def format_number(value)
    return "0" if value.nil?

    rounded = value.round(2)
    return rounded.to_i.to_s if (rounded % 1).zero?

    format("%.2f", rounded).sub(/0+\z/, "").sub(/\.$/, "")
  end

  def label_for(record_type)
    RECORD_TYPE_LABELS.fetch(record_type) do
      record_type.to_s.sub(/\AHK(?:QuantityTypeIdentifier|CategoryTypeIdentifier|DataTypeIdentifier)/, "").tr("_", " ").humanize
    end
  end
end
