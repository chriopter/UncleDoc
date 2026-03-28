module ApplicationHelper
  def formatted_date(date)
    return "Unknown" if date.blank?

    if current_date_format == "compact"
      date.strftime(current_locale == "de" ? "%d.%m.%Y" : "%m/%d/%Y")
    else
      l(date, format: :long)
    end
  end

  def settings_option_class(selected)
    base = "flex items-center justify-between rounded-2xl border px-3 py-2 text-sm font-medium transition"

    if selected
      "#{base} border-amber-300 bg-amber-50 text-slate-950"
    else
      "#{base} border-slate-200 bg-white text-slate-700 hover:border-slate-300 hover:bg-slate-50"
    end
  end
end
