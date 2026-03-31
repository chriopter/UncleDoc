module ApplicationHelper
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

  def capped_time_ago_in_words(time)
    return unless time

    seconds_ago = Time.current - time
    return time_ago_in_words(1.minute.ago) if seconds_ago < 1.minute

    time_ago_in_words(time)
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
end
