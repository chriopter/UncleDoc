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
    "HKQuantityTypeIdentifierHeartRate" => "Pulse",
    "HKQuantityTypeIdentifierRestingHeartRate" => "Resting pulse",
    "HKQuantityTypeIdentifierWalkingHeartRateAverage" => "Walking pulse",
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
    "HKCategoryTypeIdentifierSleepAnalysis" => "Sleep",
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

  HEART_RATE_TYPES = %w[
    HKQuantityTypeIdentifierHeartRate
    HKQuantityTypeIdentifierRestingHeartRate
    HKQuantityTypeIdentifierWalkingHeartRateAverage
  ].freeze

  MASS_TYPES = %w[
    HKQuantityTypeIdentifierBodyMass
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
    previous_month_start = @today.prev_month.beginning_of_month

    daily_previews = daily_aggregates.filter_map do |date, aggregate|
      next if date < previous_month_start
      next unless aggregate_has_data?(aggregate)

      build_preview(period_type: :day, starts_on: date, ends_on: date, aggregate:)
    end

    monthly_previews = daily_aggregates
      .select { |date, aggregate| date < previous_month_start && aggregate_has_data?(aggregate) }
      .group_by { |date, _aggregate| date.beginning_of_month }
      .map do |month_start, aggregates|
        month_end = month_start.end_of_month
        month_aggregate = aggregates.map(&:last).reduce(blank_aggregate(days_count: 0)) do |memo, aggregate|
          merge_aggregates(memo, aggregate)
        end

        build_preview(period_type: :month, starts_on: month_start, ends_on: month_end, aggregate: month_aggregate)
      end

    (monthly_previews + daily_previews).sort_by(&:starts_on)
  end

  private

  def build_daily_aggregates(first_date:, last_closed_day:)
    aggregates = (first_date..last_closed_day).index_with { blank_aggregate(days_count: 1) }

    @person.healthkit_records.in_batches(of: 1000) do |batch|
      batch.pluck(:record_type, :source_name, :start_at, :end_at, :payload).each do |record_type, source_name, start_at, end_at, payload|
        next unless start_at

        apply_record(
          aggregates: aggregates,
          first_date: first_date,
          last_closed_day: last_closed_day,
          record_type: record_type,
          source_name: source_name,
          start_at: start_at,
          end_at: end_at,
          payload: payload
        )
      end
    end

    aggregates.each_value do |aggregate|
      aggregate[:days_with_data] = aggregate_has_data?(aggregate) ? 1 : 0
    end

    aggregates
  end

  def apply_record(aggregates:, first_date:, last_closed_day:, record_type:, source_name:, start_at:, end_at:, payload:)
    payload_hash = normalize_payload(payload)
    quantity_value, quantity_unit = extract_quantity(payload_hash)
    value = extract_value(payload_hash)
    slices = day_duration_slices(start_at, end_at)

    if slices.empty?
      date = start_at.in_time_zone.to_date
      return unless date.between?(first_date, last_closed_day)

      update_aggregate(
        aggregates.fetch(date),
        record_type: record_type,
        source_name: source_name,
        start_at: start_at,
        count_increment: 1,
        touch_increment: 1,
        quantity_value: quantity_value,
        quantity_unit: quantity_unit,
        duration_seconds: 0,
        value: value
      )
      return
    end

    slices.each_with_index do |(date, duration_seconds), index|
      next unless date.between?(first_date, last_closed_day)

      update_aggregate(
        aggregates.fetch(date),
        record_type: record_type,
        source_name: source_name,
        start_at: start_at,
        count_increment: index.zero? ? 1 : 0,
        touch_increment: 1,
        quantity_value: index.zero? ? quantity_value : nil,
        quantity_unit: index.zero? ? quantity_unit : nil,
        duration_seconds: duration_seconds,
        value: index.zero? ? value : nil
      )
    end
  end

  def build_preview(period_type:, starts_on:, ends_on:, aggregate:)
    present_types = aggregate[:types].keys.sort
    mentioned = Set.new
    lines = [
      "- Source: Apple Health.",
      "- Summary type: #{period_type == :month ? 'monthly' : 'daily'}.",
      "- Period: #{period_label(period_type, starts_on, ends_on)}."
    ]

    lines << "- Coverage: #{aggregate[:days_with_data]} days with data, #{aggregate[:record_count]} raw records." if period_type == :month

    add_lines(lines, mentioned, movement_lines(aggregate))
    add_lines(lines, mentioned, cardio_lines(aggregate))
    add_lines(lines, mentioned, sleep_lines(aggregate))
    add_lines(lines, mentioned, nutrition_lines(aggregate))
    add_lines(lines, mentioned, body_lines(aggregate, period_type))
    add_lines(lines, mentioned, activity_lines(aggregate))
    add_lines(lines, mentioned, assessment_lines(aggregate))
    add_lines(lines, mentioned, characteristic_lines(aggregate))

    missing_types = present_types - mentioned.to_a
    if missing_types.any?
      lines << bullet("Other Apple Health data: #{missing_types.map { |record_type| "#{label_for(record_type)} (#{record_type}) #{display_count(aggregate[:types][record_type])} records" }.join('; ')}")
      mentioned.merge(missing_types)
    end

    Preview.new(
      source_ref: source_ref_for(period_type, starts_on),
      period_type: period_type,
      starts_on: starts_on,
      ends_on: ends_on,
      occurred_at: occurred_at_for(period_type, starts_on, ends_on),
      input: ([ header_for(period_type, starts_on) ] + lines).join("\n"),
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
      touch_count: 0,
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

  def update_aggregate(aggregate, record_type:, source_name:, start_at:, count_increment:, touch_increment:, quantity_value:, quantity_unit:, duration_seconds:, value:)
    aggregate[:record_count] += count_increment
    aggregate[:source_names] << source_name if source_name.present?

    type_aggregate = aggregate[:types][record_type] ||= blank_type_aggregate
    type_aggregate[:count] += count_increment
    type_aggregate[:touch_count] += touch_increment
    type_aggregate[:source_names] << source_name if source_name.present?
    type_aggregate[:first_at] = [ type_aggregate[:first_at], start_at ].compact.min
    type_aggregate[:last_at] = [ type_aggregate[:last_at], start_at ].compact.max

    if quantity_value
      quantity_value, quantity_unit = normalize_quantity_for_aggregate(record_type, quantity_value, quantity_unit)

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

    type_aggregate[:duration_seconds] += duration_seconds.to_f if duration_seconds.to_f.positive?
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
    ].select { |item| item.first.present? }.max_by(&:first)

    {
      count: left[:count] + right[:count],
      touch_count: left[:touch_count] + right[:touch_count],
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

  def movement_lines(aggregate)
    lines = []
    covered = []

    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierStepCount", unit: "count")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDistanceWalkingRunning", transform: 0.001, unit: "km")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDistanceCycling", transform: 0.001, unit: "km")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierActiveEnergyBurned", unit: "kcal")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierBasalEnergyBurned", unit: "kcal")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierFlightsClimbed", unit: "count")
    append_average_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierWalkingSpeed")
    append_average_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierWalkingStepLength")

    stand = aggregate[:types]["HKCategoryTypeIdentifierAppleStandHour"]
    if stand
      lines << bullet("#{label_for('HKCategoryTypeIdentifierAppleStandHour')} #{stand[:values]['1']} completed hours across #{display_count(stand)} records")
      covered << "HKCategoryTypeIdentifierAppleStandHour"
    end

    [ lines, covered ]
  end

  def cardio_lines(aggregate)
    lines = []
    covered = []

    append_avg_min_max(lines, covered, aggregate, "HKQuantityTypeIdentifierHeartRate")
    append_avg_min_max(lines, covered, aggregate, "HKQuantityTypeIdentifierRestingHeartRate")
    append_avg_min_max(lines, covered, aggregate, "HKQuantityTypeIdentifierWalkingHeartRateAverage")
    append_avg_min_max(lines, covered, aggregate, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
    append_avg_min_max(lines, covered, aggregate, "HKQuantityTypeIdentifierRespiratoryRate")
    append_avg_min_max(lines, covered, aggregate, "HKQuantityTypeIdentifierOxygenSaturation")
    append_avg_min_max(lines, covered, aggregate, "HKQuantityTypeIdentifierVO2Max")

    systolic = aggregate[:types]["HKQuantityTypeIdentifierBloodPressureSystolic"]
    diastolic = aggregate[:types]["HKQuantityTypeIdentifierBloodPressureDiastolic"]
    if systolic || diastolic
      lines << bullet(
        [
          blood_pressure_part("systolic", systolic),
          blood_pressure_part("diastolic", diastolic)
        ].compact.join("; ")
      )
      covered.concat([ "HKQuantityTypeIdentifierBloodPressureSystolic", "HKQuantityTypeIdentifierBloodPressureDiastolic" ].select { |type| aggregate[:types][type] })
    end

    [ lines, covered ]
  end

  def sleep_lines(aggregate)
    sleep = aggregate[:types]["HKCategoryTypeIdentifierSleepAnalysis"]
    return [ [], [] ] unless sleep

    lines = [ bullet("Sleep #{format_number(sleep[:duration_seconds] / 3600.0)} hours across #{display_count(sleep)} segments") ]
    if sleep[:values].any?
      values = sleep[:values].sort_by { |value, _count| value.to_s }.map { |value, count| "#{value} (#{count})" }.join(", ")
      lines << bullet("Sleep category values #{values}")
    end

    [ lines, [ "HKCategoryTypeIdentifierSleepAnalysis" ] ]
  end

  def nutrition_lines(aggregate)
    lines = []
    covered = []

    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDietaryEnergyConsumed", unit: "kcal")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDietaryCarbohydrates")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDietaryProtein")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDietaryFatTotal")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDietarySugar")
    append_total_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierDietaryWater")

    [ lines, covered ]
  end

  def body_lines(aggregate, period_type)
    lines = []
    covered = []

    weight = aggregate[:types]["HKQuantityTypeIdentifierBodyMass"]
    if weight&.dig(:quantity_count).to_i.positive?
      lines << if period_type == :day
        bullet("Weight #{format_number(weight[:latest_quantity_value])} #{display_unit(weight, override: 'kg')}")
      else
        bullet("Weight avg #{format_number(average_quantity(weight))} #{display_unit(weight, override: 'kg')}; min #{format_number(weight[:quantity_min])}; max #{format_number(weight[:quantity_max])}")
      end
      covered << "HKQuantityTypeIdentifierBodyMass"
    end

    append_average_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierBodyMassIndex")
    append_average_quantity(lines, covered, aggregate, "HKQuantityTypeIdentifierBodyFatPercentage")

    height = aggregate[:types]["HKQuantityTypeIdentifierHeight"]
    if height&.dig(:quantity_count).to_i.positive?
      lines << bullet("Height #{format_number(height[:latest_quantity_value])} #{display_unit(height)}")
      covered << "HKQuantityTypeIdentifierHeight"
    end

    temperature = aggregate[:types]["HKQuantityTypeIdentifierBodyTemperature"]
    if temperature&.dig(:quantity_count).to_i.positive?
      lines << if period_type == :day
        bullet("Body temperature #{format_number(temperature[:latest_quantity_value])} #{display_unit(temperature, override: 'C')}")
      else
        bullet("Body temperature avg #{format_number(average_quantity(temperature))} #{display_unit(temperature, override: 'C')}")
      end
      covered << "HKQuantityTypeIdentifierBodyTemperature"
    end

    [ lines, covered ]
  end

  def activity_lines(aggregate)
    lines = []
    covered = []

    workout = aggregate[:types]["HKWorkoutTypeIdentifier"]
    if workout
      lines << bullet("Workouts #{display_count(workout)} with #{format_number(workout[:duration_seconds] / 60.0)} total minutes")
      covered << "HKWorkoutTypeIdentifier"
    end

    audio = aggregate[:types]["HKCategoryTypeIdentifierAudioExposureEvent"]
    if audio
      lines << bullet("Audio exposure events #{display_count(audio)} with #{format_number(audio[:duration_seconds] / 60.0)} total minutes")
      covered << "HKCategoryTypeIdentifierAudioExposureEvent"
    end

    [ lines, covered ]
  end

  def assessment_lines(aggregate)
    covered = ASSESSMENT_TYPES.select { |record_type| aggregate[:types][record_type] }
    lines = covered.map do |record_type|
      bullet("#{label_for(record_type)} #{display_count(aggregate[:types][record_type])} records")
    end

    [ lines, covered ]
  end

  def characteristic_lines(aggregate)
    covered = CHARACTERISTIC_TYPES.select { |record_type| aggregate[:types][record_type] }
    lines = covered.map do |record_type|
      bullet("#{label_for(record_type)} present (#{record_type})")
    end

    [ lines, covered ]
  end

  def append_total_quantity(lines, covered, aggregate, record_type, transform: 1.0, unit: nil)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    lines << bullet("#{label_for(record_type)} #{format_number(type_aggregate[:quantity_sum] * transform)} #{display_unit(type_aggregate, override: unit)}")
    covered << record_type
  end

  def append_average_quantity(lines, covered, aggregate, record_type, unit: nil)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    avg_value = average_quantity(type_aggregate)
    avg_value, display_unit_value = normalize_quantity_for_display(record_type, avg_value, display_unit(type_aggregate, override: unit))

    lines << bullet("#{label_for(record_type)} avg #{format_number(avg_value)} #{display_unit_value}")
    covered << record_type
  end

  def append_avg_min_max(lines, covered, aggregate, record_type)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    avg_value = average_quantity(type_aggregate)
    min_value = type_aggregate[:quantity_min]
    max_value = type_aggregate[:quantity_max]
    avg_value, display_unit_value = normalize_quantity_for_display(record_type, avg_value, display_unit(type_aggregate))
    min_value, = normalize_quantity_for_display(record_type, min_value, display_unit(type_aggregate))
    max_value, = normalize_quantity_for_display(record_type, max_value, display_unit(type_aggregate))

    lines << bullet("#{label_for(record_type)} avg #{format_number(avg_value)} #{display_unit_value}; min #{format_number(min_value)}; max #{format_number(max_value)}")
    covered << record_type
  end

  def add_lines(target_lines, mentioned, payload)
    lines, record_types = payload
    return if lines.blank?

    target_lines.concat(lines)
    mentioned.merge(record_types)
  end

  def aggregate_has_data?(aggregate)
    aggregate[:types].any?
  end

  def display_count(type_aggregate)
    [ type_aggregate[:count], type_aggregate[:touch_count] ].max
  end

  def average_quantity(type_aggregate)
    return 0 if type_aggregate[:quantity_count].zero?

    type_aggregate[:quantity_sum] / type_aggregate[:quantity_count]
  end

  def display_unit(type_aggregate, override: nil)
    override.presence || type_aggregate[:unit].to_s.strip
  end

  def normalize_quantity_for_display(record_type, value, unit)
    return [ value, unit ] if value.nil?
    if HEART_RATE_TYPES.include?(record_type)
      case unit.to_s.strip.downcase
      when "count/s"
        return [ value * 60.0, "bpm" ]
      when "count/min"
        return [ value, "bpm" ]
      end
    end

    if MASS_TYPES.include?(record_type)
      case unit.to_s.strip.downcase
      when "g"
        return [ value / 1000.0, "kg" ]
      end
    end

    [ value, unit ]
  end

  def normalize_quantity_for_aggregate(record_type, value, unit)
    normalize_quantity_for_display(record_type, value, unit)
  end

  def extract_quantity(payload_hash)
    quantity = payload_hash["quantity"].to_s.strip
    return [ nil, nil ] if quantity.blank?

    match = quantity.match(/\A(-?\d+(?:\.\d+)?)\s*(.*)\z/)
    return [ nil, nil ] unless match

    [ match[1].to_f, match[2].presence ]
  end

  def extract_value(payload_hash)
    payload_hash["value"].to_s.strip.presence
  end

  def normalize_payload(payload)
    hash = case payload
    when Hash
      payload
    when String
      JSON.parse(payload)
    else
      payload.respond_to?(:to_h) ? payload.to_h : {}
    end

    hash.is_a?(Hash) ? hash.stringify_keys : {}
  rescue JSON::ParserError, TypeError
    {}
  end

  def day_duration_slices(start_at, end_at)
    return [] unless end_at.present? && end_at > start_at

    slices = []
    current_start = start_at

    while current_start < end_at
      current_day_end = current_start.end_of_day
      slice_end = [ current_day_end, end_at ].min
      duration_seconds = [ slice_end.to_f - current_start.to_f, 0 ].max
      slices << [ current_start.in_time_zone.to_date, duration_seconds ] if duration_seconds.positive?
      current_start = slice_end == end_at ? end_at : current_start.next_day.beginning_of_day
    end

    slices
  end

  def source_ref_for(period_type, starts_on)
    period_type.to_sym == :month ? "healthkit:month:#{starts_on.strftime('%Y-%m')}" : "healthkit:day:#{starts_on.iso8601}"
  end

  def occurred_at_for(period_type, starts_on, ends_on)
    period_type.to_sym == :month ? ends_on.end_of_day : starts_on.end_of_day
  end

  def header_for(period_type, starts_on)
    if period_type.to_sym == :month
      "Apple Health monthly summary for #{starts_on.strftime('%B %Y')}."
    else
      "Apple Health daily summary for #{starts_on.strftime('%B %d, %Y')}."
    end
  end

  def period_label(period_type, starts_on, ends_on)
    if period_type.to_sym == :month
      starts_on.strftime("%B %Y")
    elsif starts_on == ends_on
      starts_on.strftime("%B %d, %Y")
    else
      "#{starts_on.strftime('%B %d, %Y')} to #{ends_on.strftime('%B %d, %Y')}"
    end
  end

  def bullet(text)
    "- #{text}."
  end

  def blood_pressure_part(kind, aggregate)
    return unless aggregate&.dig(:quantity_count).to_i.positive?

    "Blood pressure #{kind} avg #{format_number(average_quantity(aggregate))} #{display_unit(aggregate, override: 'mmHg')}"
  end

  def format_number(value)
    return "0" if value.nil?

    rounded = value.round(2)
    return rounded.to_i.to_s if (rounded % 1).zero?

    format("%.2f", rounded).sub(/0+\z/, "").sub(/\.$/, "")
  end

  def label_for(record_type)
    RECORD_TYPE_LABELS.fetch(record_type, record_type)
  end
end
