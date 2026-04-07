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
    previous_month_start = @today.prev_month.beginning_of_month

    daily_previews = daily_aggregates.filter_map do |date, aggregate|
      next if date < previous_month_start

      build_preview(period_type: :day, starts_on: date, ends_on: date, aggregate:)
    end

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
    return empty_preview(period_type:, starts_on:, ends_on:) unless aggregate_has_data?(aggregate)

    sections = []
    mentioned = Set.new
    present_types = aggregate[:types].keys.sort

    add_section(sections, mentioned, movement_section(aggregate))
    add_section(sections, mentioned, cardio_section(aggregate))
    add_section(sections, mentioned, sleep_section(aggregate))
    add_section(sections, mentioned, nutrition_section(aggregate))
    add_section(sections, mentioned, body_section(aggregate, period_type))
    add_section(sections, mentioned, activities_section(aggregate))
    add_section(sections, mentioned, assessments_section(aggregate))
    add_section(sections, mentioned, characteristics_section(aggregate))

    missing_types = present_types - mentioned.to_a
    if missing_types.any?
      sections << section_text(:other, other_items(aggregate, missing_types))
      mentioned.merge(missing_types)
    end

    Preview.new(
      source_ref: source_ref_for(period_type, starts_on),
      period_type: period_type,
      starts_on: starts_on,
      ends_on: ends_on,
      occurred_at: occurred_at_for(period_type, starts_on, ends_on),
      input: [ header_for(period_type, starts_on), coverage_sentence(period_type, aggregate), *sections ].compact.join("\n\n"),
      present_record_types: present_types,
      mentioned_record_types: mentioned.to_a.sort,
      missing_record_types: present_types - mentioned.to_a,
      record_count: aggregate[:record_count]
    )
  end

  def empty_preview(period_type:, starts_on:, ends_on:)
    Preview.new(
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

  def movement_section(aggregate)
    items = []
    covered = []

    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierStepCount", unit: "count")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDistanceWalkingRunning", transform: 0.001, unit: "km")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDistanceCycling", transform: 0.001, unit: "km")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierActiveEnergyBurned", unit: "kcal")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierBasalEnergyBurned", unit: "kcal")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierFlightsClimbed", unit: "count")
    append_average_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierWalkingSpeed")
    append_average_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierWalkingStepLength")

    stand = aggregate[:types]["HKCategoryTypeIdentifierAppleStandHour"]
    if stand
      items << I18n.t(
        "healthkit.preview.items.completed_hours",
        label: label_for("HKCategoryTypeIdentifierAppleStandHour"),
        completed: stand[:values]["1"],
        count: display_count(stand)
      )
      covered << "HKCategoryTypeIdentifierAppleStandHour"
    end

    return if items.empty?

    [ section_text(:movement, items), covered ]
  end

  def cardio_section(aggregate)
    items = []
    covered = []

    append_avg_min_max(items, covered, aggregate, "HKQuantityTypeIdentifierHeartRate")
    append_avg_min_max(items, covered, aggregate, "HKQuantityTypeIdentifierRestingHeartRate")
    append_avg_min_max(items, covered, aggregate, "HKQuantityTypeIdentifierWalkingHeartRateAverage")
    append_avg_min_max(items, covered, aggregate, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
    append_avg_min_max(items, covered, aggregate, "HKQuantityTypeIdentifierRespiratoryRate")
    append_avg_min_max(items, covered, aggregate, "HKQuantityTypeIdentifierOxygenSaturation")
    append_avg_min_max(items, covered, aggregate, "HKQuantityTypeIdentifierVO2Max")

    systolic = aggregate[:types]["HKQuantityTypeIdentifierBloodPressureSystolic"]
    diastolic = aggregate[:types]["HKQuantityTypeIdentifierBloodPressureDiastolic"]
    if systolic || diastolic
      parts = []
      if systolic&.dig(:quantity_count).to_i.positive?
        parts << I18n.t("healthkit.preview.items.systolic_avg", value: format_number(average_quantity(systolic)), unit: display_unit(systolic, override: "mmHg"))
      end
      if diastolic&.dig(:quantity_count).to_i.positive?
        parts << I18n.t("healthkit.preview.items.diastolic_avg", value: format_number(average_quantity(diastolic)), unit: display_unit(diastolic, override: "mmHg"))
      end
      items << I18n.t("healthkit.preview.items.blood_pressure", parts: parts.join(", "))
      covered.concat([ "HKQuantityTypeIdentifierBloodPressureSystolic", "HKQuantityTypeIdentifierBloodPressureDiastolic" ].select { |type| aggregate[:types][type] })
    end

    return if items.empty?

    [ section_text(:cardio, items), covered ]
  end

  def sleep_section(aggregate)
    sleep = aggregate[:types]["HKCategoryTypeIdentifierSleepAnalysis"]
    return unless sleep

    items = [
      I18n.t(
        "healthkit.preview.items.sleep_duration",
        label: label_for("HKCategoryTypeIdentifierSleepAnalysis"),
        hours: format_number(sleep[:duration_seconds] / 3600.0),
        count: display_count(sleep)
      )
    ]

    if sleep[:values].any?
      values = sleep[:values].sort_by { |value, _count| value.to_s }.map { |value, count| "#{value} (#{count})" }.join(", ")
      items << I18n.t("healthkit.preview.items.sleep_values", values: values)
    end

    [ section_text(:sleep, items), [ "HKCategoryTypeIdentifierSleepAnalysis" ] ]
  end

  def nutrition_section(aggregate)
    items = []
    covered = []

    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDietaryEnergyConsumed", unit: "kcal")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDietaryCarbohydrates")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDietaryProtein")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDietaryFatTotal")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDietarySugar")
    append_total_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierDietaryWater")

    return if items.empty?

    [ section_text(:nutrition, items), covered ]
  end

  def body_section(aggregate, period_type)
    items = []
    covered = []

    weight = aggregate[:types]["HKQuantityTypeIdentifierBodyMass"]
    if weight&.dig(:quantity_count).to_i.positive?
      items << if period_type == :day
        quantity_item("HKQuantityTypeIdentifierBodyMass", format_number(weight[:latest_quantity_value]), display_unit(weight, override: "kg"))
      else
        avg_min_max_item("HKQuantityTypeIdentifierBodyMass", weight, unit: "kg")
      end
      covered << "HKQuantityTypeIdentifierBodyMass"
    end

    append_average_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierBodyMassIndex")
    append_average_quantity(items, covered, aggregate, "HKQuantityTypeIdentifierBodyFatPercentage")

    height = aggregate[:types]["HKQuantityTypeIdentifierHeight"]
    if height&.dig(:quantity_count).to_i.positive?
      items << quantity_item("HKQuantityTypeIdentifierHeight", format_number(height[:latest_quantity_value]), display_unit(height))
      covered << "HKQuantityTypeIdentifierHeight"
    end

    temperature = aggregate[:types]["HKQuantityTypeIdentifierBodyTemperature"]
    if temperature&.dig(:quantity_count).to_i.positive?
      items << if period_type == :day
        quantity_item("HKQuantityTypeIdentifierBodyTemperature", format_number(temperature[:latest_quantity_value]), display_unit(temperature, override: "C"))
      else
        average_item("HKQuantityTypeIdentifierBodyTemperature", average_quantity(temperature), display_unit(temperature, override: "C"))
      end
      covered << "HKQuantityTypeIdentifierBodyTemperature"
    end

    return if items.empty?

    [ section_text(:body, items), covered ]
  end

  def activities_section(aggregate)
    items = []
    covered = []

    workout = aggregate[:types]["HKWorkoutTypeIdentifier"]
    if workout
      items << I18n.t("healthkit.preview.items.count_with_minutes", label: label_for("HKWorkoutTypeIdentifier"), count: display_count(workout), minutes: format_number(workout[:duration_seconds] / 60.0))
      covered << "HKWorkoutTypeIdentifier"
    end

    audio = aggregate[:types]["HKCategoryTypeIdentifierAudioExposureEvent"]
    if audio
      items << I18n.t("healthkit.preview.items.count_with_minutes", label: label_for("HKCategoryTypeIdentifierAudioExposureEvent"), count: display_count(audio), minutes: format_number(audio[:duration_seconds] / 60.0))
      covered << "HKCategoryTypeIdentifierAudioExposureEvent"
    end

    return if items.empty?

    [ section_text(:activities, items), covered ]
  end

  def assessments_section(aggregate)
    covered = ASSESSMENT_TYPES.select { |record_type| aggregate[:types][record_type] }
    return if covered.empty?

    items = covered.map do |record_type|
      type_aggregate = aggregate[:types][record_type]
      I18n.t("healthkit.preview.items.count_records", label: label_for(record_type), count: display_count(type_aggregate))
    end

    [ section_text(:assessments, items), covered ]
  end

  def characteristics_section(aggregate)
    covered = CHARACTERISTIC_TYPES.select { |record_type| aggregate[:types][record_type] }
    return if covered.empty?

    items = covered.map do |record_type|
      I18n.t("healthkit.preview.items.characteristic", label: label_for(record_type), record_type: record_type)
    end

    [ section_text(:characteristics, items), covered ]
  end

  def other_items(aggregate, record_types)
    record_types.map do |record_type|
      type_aggregate = aggregate[:types][record_type]
      I18n.t("healthkit.preview.items.other_record", label: label_for(record_type), record_type: record_type, count: display_count(type_aggregate))
    end
  end

  def append_total_quantity(items, covered, aggregate, record_type, transform: 1.0, unit: nil)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    items << quantity_item(record_type, format_number(type_aggregate[:quantity_sum] * transform), display_unit(type_aggregate, override: unit))
    covered << record_type
  end

  def append_average_quantity(items, covered, aggregate, record_type, unit: nil)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    items << average_item(record_type, average_quantity(type_aggregate), display_unit(type_aggregate, override: unit))
    covered << record_type
  end

  def append_avg_min_max(items, covered, aggregate, record_type)
    type_aggregate = aggregate[:types][record_type]
    return unless type_aggregate&.dig(:quantity_count).to_i.positive?

    items << avg_min_max_item(record_type, type_aggregate)
    covered << record_type
  end

  def quantity_item(record_type, value, unit)
    I18n.t("healthkit.preview.items.quantity", label: label_for(record_type), value: value, unit: unit)
  end

  def average_item(record_type, value, unit)
    I18n.t("healthkit.preview.items.average", label: label_for(record_type), value: format_number(value), unit: unit, avg_label: metric_label(:avg))
  end

  def avg_min_max_item(record_type, type_aggregate, unit: nil)
    I18n.t(
      "healthkit.preview.items.avg_min_max",
      label: label_for(record_type),
      avg_label: metric_label(:avg),
      min_label: metric_label(:min),
      max_label: metric_label(:max),
      avg_value: format_number(average_quantity(type_aggregate)),
      min_value: format_number(type_aggregate[:quantity_min]),
      max_value: format_number(type_aggregate[:quantity_max]),
      unit: display_unit(type_aggregate, override: unit)
    )
  end

  def section_text(section_key, items)
    I18n.t("healthkit.preview.section_sentence", label: I18n.t("healthkit.preview.sections.#{section_key}"), items: items.join(". "))
  end

  def add_section(sections, mentioned, section)
    return unless section

    text, record_types = section
    return if text.blank?

    sections << text
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
    return override if override.present?

    type_aggregate[:unit].to_s.strip
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
    if period_type.to_sym == :month
      "healthkit:month:#{starts_on.strftime('%Y-%m')}"
    else
      "healthkit:day:#{starts_on.iso8601}"
    end
  end

  def occurred_at_for(period_type, starts_on, ends_on)
    if period_type.to_sym == :month
      ends_on.end_of_day
    else
      starts_on.end_of_day
    end
  end

  def header_for(period_type, starts_on)
    if period_type.to_sym == :month
      I18n.t("healthkit.preview.headers.month", date: I18n.l(starts_on, format: "%B %Y"))
    else
      I18n.t("healthkit.preview.headers.day", date: I18n.l(starts_on, format: :long_date))
    end
  end

  def coverage_sentence(period_type, aggregate)
    return if period_type.to_sym == :day

    I18n.t(
      "healthkit.preview.coverage",
      days_count: aggregate[:days_count],
      days_with_data: aggregate[:days_with_data],
      record_count: aggregate[:record_count]
    )
  end

  def empty_input_for(period_type, starts_on)
    if period_type.to_sym == :month
      I18n.t("healthkit.preview.headers.empty_month", date: I18n.l(starts_on, format: "%B %Y"))
    else
      I18n.t("healthkit.preview.headers.empty_day", date: I18n.l(starts_on, format: :long_date))
    end
  end

  def metric_label(key)
    I18n.t("healthkit.preview.metrics.#{key}")
  end

  def format_number(value)
    return "0" if value.nil?

    rounded = value.round(2)
    return rounded.to_i.to_s if (rounded % 1).zero?

    format("%.2f", rounded).sub(/0+\z/, "").sub(/\.$/, "")
  end

  def label_for(record_type)
    I18n.t("healthkit.preview.record_types.#{record_type_key(record_type)}", default: record_type)
  end

  def record_type_key(record_type)
    record_type.to_s.tr(".", "_").underscore
  end
end
