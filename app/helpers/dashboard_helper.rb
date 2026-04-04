module DashboardHelper
  def shell_nav_items(current_person, request_path)
    return [{ label: t("nav.home"), path: root_path, active: current_page?(root_path) }] unless current_person

    items = [
      { label: t("nav.overview"), path: person_overview_path(person_slug: current_person.name), active: request_path.include?("/overview") }
    ]

    if current_person.baby_mode?
      items << { label: t("nav.baby"), path: person_baby_path(person_slug: current_person.name), active: request_path.include?("/baby"), child: true }
    end

    items << { label: t("nav.research"), path: person_log_path(person_slug: current_person.name), active: request_path.include?("/log") }
    items << { label: t("nav.data"), path: person_files_path(person_slug: current_person.name), active: request_path.include?("/files") }
    items << { label: t("nav.files"), path: person_files_path(person_slug: current_person.name), active: request_path.include?("/files"), child: true }

    items
  end

  def shell_settings_items(request_path)
    return [] unless request_path.start_with?("/settings")

    [
      { label: t("settings.profile.nav"), path: settings_path_for(:profile), active: request_path == settings_path_for(:profile) || request_path == "/settings", child: true },
      { label: t("settings.users.nav"), path: settings_path_for(:users), active: request_path == settings_path_for(:users), child: true },
      { label: t("settings.llm.title"), path: settings_path_for(:llm), active: request_path.include?("llm"), child: true },
      { label: t("settings.db.title"), path: settings_path_for(:db), active: request_path == settings_path_for(:db), child: true }
    ]
  end

  def shell_menu_item_class(active = false)
    base = "flex items-center rounded-xl px-3 py-2 text-sm font-semibold transition"

    if active
      "#{base} bg-slate-950 text-white shadow-sm"
    else
      "#{base} text-slate-700 hover:bg-white hover:text-slate-950"
    end
  end

  def shell_nav_icon(label)
    case label
    when t("nav.overview")
      "M3 12h7V3H3zm11 9h7v-7h-7zm0-18v7h7V3zM3 21h7v-7H3z"
    when t("nav.log")
      "M8 7h8M8 12h8m-8 5h5M6 3h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z"
    when t("nav.research")
      "M21 21l-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"
    when t("nav.data")
      "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"
    when t("nav.files")
      "M7 18a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h5l2 2h3a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2Z"
    when t("nav.baby")
      "M12 5c1.7 0 3 1.3 3 3s-1.3 3-3 3-3-1.3-3-3 1.3-3 3-3Zm-5 13c0-2.8 2.2-5 5-5s5 2.2 5 5"
    when t("nav.settings")
      "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 0 0 2.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 0 0 1.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 0 0-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 0 0-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 0 0-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 0 0-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35A1.724 1.724 0 0 0 5.383 7.75c-.94-1.543.826-3.31 2.37-2.37 1 .608 2.296.07 2.572-1.065ZM12 15.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5Z"
    else
      "M4 12h16"
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
