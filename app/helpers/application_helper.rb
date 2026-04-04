module ApplicationHelper
  def app_revision_tooltip
    details = app_revision_details
    return unless details

    t("app.revision.tooltip", subject: details[:subject], sha: details[:short_sha])
  end

  def app_revision_details
    sha = ENV["KAMAL_VERSION"].presence || ENV["APP_REVISION"].presence || local_git_sha
    subject = ENV["APP_COMMIT_SUBJECT"].presence || local_git_subject
    return if sha.blank? || subject.blank?

    { sha: sha, short_sha: sha.first(7), subject: subject }
  end

  def formatted_date(date)
    return "Unknown" if date.blank?

    if current_date_format == "compact"
      date.strftime(current_locale == "de" ? "%d.%m.%Y" : "%m/%d/%Y")
    else
      l(date, format: :long)
    end
  end

  def formatted_birth_date(datetime)
    return t("person.overview.birth_date_not_set") if datetime.blank?

    if current_date_format == "compact"
      datetime.strftime(current_locale == "de" ? "%d.%m.%Y %H:%M" : "%m/%d/%Y %I:%M %p")
    else
      l(datetime, format: :long)
    end
  end

  def person_age_label(birth_date)
    return "-" if birth_date.blank?

    duration = Time.current - birth_date
    days = (duration / 1.day).floor
    weeks = (duration / 1.week).floor
    months = (duration / 30.44.days).floor
    years = (duration / 365.25.days).floor

    if days < 14
      t("person.overview.age.days", count: [ days, 0 ].max)
    elsif weeks < 12
      t("person.overview.age.weeks", count: weeks)
    elsif months < 24
      t("person.overview.age.months", count: [ months, 1 ].max)
    else
      t("person.overview.age.years", count: [ years, 1 ].max)
    end
  end

  def grouped_entries_by_day(entries)
    entries.group_by { |entry| entry.display_time.to_date }
  end

  def log_day_label(date)
    return t("entries.day_groups.today") if date == Time.zone.today

    formatted_date(date)
  end

  def settings_option_class(selected)
    base = "flex items-center justify-between rounded-2xl border px-3 py-2 text-sm font-medium transition"

    if selected
      "#{base} border-amber-300 bg-amber-50 text-slate-950"
    else
      "#{base} border-slate-200 bg-white text-slate-700 hover:border-slate-300 hover:bg-slate-50"
    end
  end

  def settings_subnav_item_class(selected)
    base = "block rounded-xl px-3 py-2 text-xs font-medium transition"

    if selected
      "#{base} bg-amber-50 text-amber-900"
    else
      "#{base} text-slate-600 hover:bg-slate-50 hover:text-slate-900"
    end
  end

  def baby_feeding_timer_elapsed_label(started_at)
    return unless started_at

    duration_minutes = [ ((Time.current - started_at) / 60).round, 1 ].max
    t("baby.feeding.timer.duration", duration: duration_minutes)
  end

  def baby_sleep_timer_elapsed_label(started_at)
    return unless started_at

    duration_minutes = [ ((Time.current - started_at) / 60).round, 1 ].max
    t("baby.sleep.timer.duration", duration: duration_minutes)
  end

  def feeding_session_label(started_at, ended_at)
    return unless started_at && ended_at

    start_time = I18n.l(started_at, format: "%H:%M")
    end_time = I18n.l(ended_at, format: "%H:%M")

    if started_at.to_date == ended_at.to_date
      if started_at.to_date == Time.zone.today
        "#{start_time}-#{end_time}"
      else
        "#{I18n.l(started_at, format: "%-d %b")} #{start_time}-#{end_time}"
      end
    else
      "#{I18n.l(started_at, format: "%-d %b #{start_time}")}-#{I18n.l(ended_at, format: "%-d %b #{end_time}")}"
    end
  end

  def diaper_event_label(entry)
    labels = []
    labels << t("baby.diaper.buttons.wet") if entry.diaper_wet?
    labels << t("baby.diaper.buttons.solid") if entry.diaper_solid?
    labels = [ t("baby.diaper.buttons.both") ] if entry.diaper_wet? && entry.diaper_solid?
    labels << t("baby.diaper.rash") if entry.diaper_rash?
    labels.join(" · ")
  end

  def capped_time_ago_in_words(time)
    return unless time

    seconds_ago = Time.current - time
    return time_ago_in_words(1.minute.ago) if seconds_ago < 1.minute

    time_ago_in_words(time)
  end

  def compact_time_ago_label(time)
    return unless time

    minutes_ago = [ ((Time.current - time) / 60).floor, 1 ].max

    if minutes_ago < 360
      t("time.compact.minutes_ago", count: minutes_ago)
    else
      hours_ago = [ (minutes_ago / 60.0).round, 1 ].max
      t("time.compact.hours_ago", count: hours_ago)
    end
  end

  def entry_sort_mode(params_or_mode)
    mode = if params_or_mode.respond_to?(:to_unsafe_h) || params_or_mode.is_a?(Hash)
      params_or_mode[:sort]
    else
      params_or_mode
    end
    mode.to_s == "entered" ? "entered" : "occurred"
  end

  def entry_sort_label(mode)
    t("entries.sort.#{entry_sort_mode(mode)}")
  end

  def log_filter_params(overrides = {})
    params.permit(:sort, :date, :parseable_type).to_h.symbolize_keys.merge(overrides).compact
  end

  def log_filter_date_label(date)
    I18n.l(date, format: "%A, %d.%m.%Y")
  end

  def overview_widget_params(overrides = {})
    params.permit(:sort, :recent_range, :feeding_range, :diaper_range, :sleep_range, :weight_range, :height_range).to_h.symbolize_keys.merge(overrides).compact
  end

  def person_widgets_path(person, overrides = {})
    path_params = { person_slug: person.name, **overview_widget_params(overrides) }
    params[:action] == "baby" ? person_baby_path(**path_params) : person_overview_path(**path_params)
  end

  def widget_context_for(person)
    return :baby if params[:action] == "baby"
    return :baby if request.referer.to_s.include?(person_baby_path(person_slug: person.name))

    :overview
  end

  def chart_widget_card_classes
    "xl:col-span-2 xl:row-span-2 h-full"
  end

  def baby_quick_card_classes_for(person)
    widget_context_for(person) == :baby ? "xl:col-span-2 xl:row-span-3 h-full" : nil
  end

  def recent_activity_card_classes_for(person)
    if widget_context_for(person) == :baby
      "xl:col-span-4 xl:row-span-4 h-full"
    else
      "xl:col-span-2 xl:row-span-3 h-full"
    end
  end

  def overview_period_mode(params_or_hash, key)
    source = if params_or_hash.respond_to?(:to_unsafe_h) || params_or_hash.is_a?(Hash)
      params_or_hash["#{key}_range"] || params_or_hash["#{key}_range".to_sym]
    else
      params_or_hash
    end

    %w[1w 1m 1j].include?(source.to_s) ? source.to_s : "1w"
  end

  def overview_period_options
    [ [ "1W", "1w" ], [ "1M", "1m" ], [ "1J", "1j" ] ]
  end

  def overview_period_window(period)
    case period.to_s
    when "1m"
      29.days.ago.beginning_of_day..Time.zone.now.end_of_day
    when "1j"
      1.year.ago.beginning_of_day..Time.zone.now.end_of_day
    else
      6.days.ago.beginning_of_day..Time.zone.now.end_of_day
    end
  end

  def overview_recent_entries(person, sort_mode:, period:, limit: 3)
    scope = person.entries.merge(Entry.sorted_by(sort_mode)).where(occurred_at: overview_period_window(period))
    scope.limit(limit)
  end

  def weight_activity_available?(person)
    person.entries.merge(Entry.by_parseable_data_type("weight")).exists?
  end

  def height_activity_available?(person)
    person.entries.merge(Entry.by_parseable_data_type("height")).exists?
  end

  def vital_activity_available?(person, type)
    person.entries.merge(Entry.by_parseable_data_type(type.to_s)).exists?
  end

  def vital_activity_series(person, type, period: "1w")
    entries = person.entries.merge(Entry.by_parseable_data_type(type.to_s))
    buckets = case period.to_s
    when "1m"
      build_day_buckets(Time.zone.today - 24.days, 5, 5.days)
    when "1j"
      build_month_buckets(6)
    else
      build_day_buckets(Time.zone.today - 6.days, 7, 1.day)
    end

    buckets.filter_map do |bucket|
      entry = entries.where(occurred_at: bucket[:range]).order(occurred_at: :desc, created_at: :desc).first
      next unless entry

      item = entry.first_parseable_data_of_type(type.to_s)
      next unless item

      value = case type.to_s
      when "blood_pressure"
        next if item["systolic"].blank? || item["diastolic"].blank?
        item["systolic"].to_f
      else
        next if item["value"].blank?
        item["value"].to_f
      end

      {
        date: bucket[:date],
        short_label: bucket[:short_label],
        value: value,
        unit: item["unit"] || default_vital_unit(type),
        secondary: (type.to_s == "blood_pressure" ? item["diastolic"] : nil)
      }
    end
  end

  def default_vital_unit(type)
    case type.to_s
    when "temperature" then "C"
    when "pulse" then "bpm"
    when "blood_pressure" then "mmHg"
    end
  end

  def appointment_entries(person, limit: 6)
    person.entries.merge(Entry.by_parseable_data_type("appointment")).where("occurred_at >= ?", Time.zone.now.beginning_of_day).order(occurred_at: :asc, created_at: :asc).limit(limit)
  end

  def appointment_activity_available?(person)
    person.entries.merge(Entry.by_parseable_data_type("appointment")).exists?
  end

  def todo_entries(person, limit: 6)
    person.entries.merge(Entry.by_parseable_data_type("todo")).recent_first.limit(limit)
  end

  def todo_activity_available?(person)
    person.entries.merge(Entry.by_parseable_data_type("todo")).exists?
  end

  def baby_activity_series(person, type, period: "1w")
    entries = person.entries.where(occurred_at: overview_period_window(period))

    buckets = case period.to_s
    when "1m"
      build_day_buckets(Time.zone.today - 24.days, 5, 5.days)
    when "1j"
      build_month_buckets(6)
    else
      build_day_buckets(Time.zone.today - 6.days, 7, 1.day)
    end

    buckets.map do |bucket|
      count = entries.count do |entry|
        matches_type = case type
        when :feeding then baby_feeding_activity_entry?(entry)
        when :sleep then baby_sleep_activity_entry?(entry)
        else baby_diaper_activity_entry?(entry)
        end
        matches_type && bucket[:range].cover?(entry.display_time)
      end

      {
        date: bucket[:date],
        day_label: bucket[:day_label],
        short_label: bucket[:short_label],
        count: count
      }
    end
  end

  def baby_activity_bar_height(count, max_count)
    return 12 if count.zero? || max_count.zero?

    [ [ (count.to_f / max_count * 100).round, 18 ].max, 100 ].min
  end

  def weight_activity_series(person, period: "1w")
    entries = person.entries
      .merge(Entry.by_parseable_data_type("weight"))

    buckets = case period.to_s
    when "1m"
      build_day_buckets(Time.zone.today - 24.days, 5, 5.days)
    when "1j"
      build_month_buckets(6)
    else
      build_day_buckets(Time.zone.today - 6.days, 7, 1.day)
    end

    buckets.filter_map do |bucket|
      entry = entries.where(occurred_at: bucket[:range]).order(occurred_at: :desc, created_at: :desc).first
      next unless entry

        item = entry.first_parseable_data_of_type("weight")
        value = item&.dig("value")
        unit = item&.dig("unit") || "kg"
        next unless value.present?

        {
          date: bucket[:date],
          day_label: bucket[:day_label],
          short_label: bucket[:short_label],
          value: value.to_f,
          unit: unit
        }
      end
  end

  def height_activity_series(person, period: "1w")
    entries = person.entries.merge(Entry.by_parseable_data_type("height"))
    buckets = case period.to_s
    when "1m"
      build_day_buckets(Time.zone.today - 24.days, 5, 5.days)
    when "1j"
      build_month_buckets(6)
    else
      build_day_buckets(Time.zone.today - 6.days, 7, 1.day)
    end

    buckets.filter_map do |bucket|
      entry = entries.where(occurred_at: bucket[:range]).order(occurred_at: :desc, created_at: :desc).first
      next unless entry

      item = entry.first_parseable_data_of_type("height")
      value = item&.dig("value")
      unit = item&.dig("unit") || "cm"
      next unless value.present?

      {
        date: bucket[:date],
        day_label: bucket[:day_label],
        short_label: bucket[:short_label],
        value: value.to_f,
        unit: unit
      }
    end
  end

  def weight_activity_plot_points(series)
    return [] if series.blank?

    min_value = series.map { |point| point[:value] }.min
    max_value = series.map { |point| point[:value] }.max
    range = max_value - min_value
    min_x = 8.0
    max_x = 92.0
    min_y = 8.0
    max_y = 52.0
    step_x = series.length > 1 ? (max_x - min_x) / (series.length - 1) : 0

    series.each_with_index.map do |point, index|
      x = (min_x + step_x * index).round(2)
      y = if range.zero?
        30
      else
        (max_y - (((point[:value] - min_value) / range.to_f) * (max_y - min_y))).round(2)
      end
      { x: x, y: y, value: point[:value], short_label: point[:short_label] }
    end
  end

  def weight_activity_line_points(series)
    weight_activity_plot_points(series).map { |point| "#{point[:x]},#{point[:y]}" }.join(" ")
  end

  def build_day_buckets(start_date, count, step)
    count.times.map do |index|
      bucket_start = (start_date + (step * index)).beginning_of_day
      bucket_end = [ bucket_start + step - 1.second, Time.zone.now.end_of_day ].min
      {
        date: bucket_end.to_date,
        range: bucket_start..bucket_end,
        day_label: I18n.l(bucket_end.to_date, format: count >= 7 ? "%a" : "%d.%m"),
        short_label: I18n.l(bucket_end.to_date, format: "%d.%m")
      }
    end
  end

  def build_month_buckets(count)
    count.times.map do |index|
      month_date = (Time.zone.today.beginning_of_month - (count - 1 - index).months)
      {
        date: month_date.to_date,
        range: month_date.beginning_of_month..month_date.end_of_month.end_of_day,
        day_label: I18n.l(month_date.to_date, format: "%b"),
        short_label: I18n.l(month_date.to_date, format: "%b")
      }
    end
  end

  def baby_feeding_activity_entry?(entry)
    return true if entry.feeding?

    entry.input.to_s.downcase.match?(/trinken|stillen|flasche|bottle|breast/i)
  end

  def baby_diaper_activity_entry?(entry)
    return true if entry.diaper?

    entry.input.to_s.downcase.match?(/windel|diaper/i)
  end

  def baby_sleep_activity_entry?(entry)
    return true if entry.sleep?

    entry.input.to_s.downcase.match?(/sleep|schlaf/i)
  end

  private

  def local_git_sha
    @local_git_sha ||= `git rev-parse HEAD 2>/dev/null`.strip.presence
  end

  def local_git_subject
    @local_git_subject ||= `git log -1 --pretty=%s 2>/dev/null`.strip.presence
  end
end
