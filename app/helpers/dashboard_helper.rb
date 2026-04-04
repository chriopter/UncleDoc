module DashboardHelper
  def shell_nav_items(current_person, request_path)
    return [ { label: t("nav.home"), path: root_path, active: current_page?(root_path) } ] unless current_person

    items = [
      {
        label: t("nav.overview"),
        path: person_overview_path(person_slug: current_person.name),
        active: request_path.include?("/overview")
      },
      {
        label: t("nav.log"),
        path: person_log_path(person_slug: current_person.name),
        active: request_path.include?("/log")
      }
    ]

    if current_person.baby_mode?
      items.insert(1, {
        label: t("nav.baby"),
        path: person_baby_path(person_slug: current_person.name),
        active: request_path.include?("/baby")
      })
    end

    items
  end

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
