module DashboardHelper
  def dashboard_tab_class(name, active_tab)
    base = "inline-flex items-center rounded-full border px-4 py-2 text-sm font-semibold transition"

    if name == active_tab
      "#{base} border-slate-900 bg-slate-900 text-white"
    else
      "#{base} border-slate-300 bg-white text-slate-700 hover:border-slate-500"
    end
  end
end
