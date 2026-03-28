module DashboardHelper
  def shell_menu_item_class(active = false)
    base = "inline-flex items-center rounded-full px-3 py-2 text-sm font-semibold transition"

    if active
      "#{base} bg-slate-950 text-white shadow-sm"
    else
      "#{base} text-slate-700 hover:bg-white/80 hover:text-slate-950"
    end
  end

  def settings_sidebar_item_class(active = false)
    base = "flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold transition"

    if active
      "#{base} bg-slate-950 text-white shadow-sm"
    else
      "#{base} bg-white text-slate-700 hover:bg-slate-100 hover:text-slate-950"
    end
  end
end
