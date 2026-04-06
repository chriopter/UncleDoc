module DashboardHelper
  def shell_nav_items(current_person, request_path)
    return [{ label: t("nav.home"), path: root_path, active: current_page?(root_path) }] unless current_person

    items = [
      { label: t("nav.overview"), path: person_overview_path(person_slug: current_person.name), active: request_path.include?("/overview") }
    ]

    items << { label: t("nav.trends"), path: person_trends_path(person_slug: current_person.name), active: request_path.include?("/trends"), child: true }

    if current_person.baby_mode?
      items << { label: t("nav.baby"), path: person_baby_path(person_slug: current_person.name), active: request_path.include?("/baby"), child: true }
    end

    items << { label: t("nav.calendar"), path: person_calendar_path(person_slug: current_person.name), active: request_path.include?("/calendar"), child: true }

    items << { label: t("nav.research"), path: person_log_path(person_slug: current_person.name), active: request_path.include?("/log") }
    items << { label: t("nav.data"), path: person_files_path(person_slug: current_person.name), active: request_path.include?("/files") }

    items
  end

  def shell_mobile_nav_groups(current_person, request_path)
    shell_nav_items(current_person, request_path).each_with_object([]) do |item, groups|
      if item[:child] && groups.last.present?
        groups.last[:children] << item
      else
        groups << item.merge(children: [])
      end
    end
  end

  def shell_settings_items(request_path)
    [
      { label: t("settings.user_group.label"), path: settings_path_for(:profile), active: request_path == settings_path_for(:profile) || request_path == settings_path_for(:users) || request_path == "/settings" },
      { label: t("settings.profile.nav"), path: settings_path_for(:profile), active: request_path == settings_path_for(:profile) || request_path == "/settings", child: true },
      { label: t("settings.users.nav"), path: settings_path_for(:users), active: request_path == settings_path_for(:users), child: true },
      { label: t("settings.llm.title"), path: settings_path_for(:llm), active: request_path.include?("llm") },
      { label: t("settings.llm_prompt.nav"), path: settings_path_for(:llm_prompt), active: request_path == settings_path_for(:llm_prompt), child: true },
      { label: t("settings.llm_prompt_preview.nav"), path: settings_path_for(:llm_prompt_preview), active: request_path == settings_path_for(:llm_prompt_preview), child: true },
      { label: t("settings.llm_logs.nav"), path: settings_path_for(:llm_logs), active: request_path == settings_path_for(:llm_logs), child: true },
      { label: t("settings.db.title"), path: settings_path_for(:db), active: request_path.include?("db") }
    ]
  end

  def shell_db_tables
    connection = ActiveRecord::Base.connection
    data_tables = %w[entries people]
    log_tables = %w[llm_logs]
    system_tables = %w[ar_internal_metadata schema_migrations user_preferences]

    all = connection.tables.sort.map do |name|
      { name: name, count: connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(name)}").to_i }
    end

    groups = []
    groups << { label: t("db.groups.data"), tables: all.select { |t| data_tables.include?(t[:name]) } }
    groups << { label: t("db.groups.logs"), tables: all.select { |t| log_tables.include?(t[:name]) } }
    groups << { label: t("db.groups.system"), tables: all.select { |t| system_tables.include?(t[:name]) } }
    others = all.reject { |t| (data_tables + log_tables + system_tables).include?(t[:name]) }
    groups << { label: t("db.groups.other"), tables: others } if others.any?
    groups
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
    when t("nav.trends")
      "M3 17l4-4 4 4 4-8 4 4"
    when t("nav.baby")
      "M12 5c1.7 0 3 1.3 3 3s-1.3 3-3 3-3-1.3-3-3 1.3-3 3-3Zm-5 13c0-2.8 2.2-5 5-5s5 2.2 5 5"
    when t("nav.settings")
      "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 0 0 2.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 0 0 1.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 0 0-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 0 0-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 0 0-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 0 0-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35A1.724 1.724 0 0 0 5.383 7.75c-.94-1.543.826-3.31 2.37-2.37 1 .608 2.296.07 2.572-1.065ZM12 15.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5Z"
    when t("settings.user_group.label")
      "M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z"
    when t("settings.llm.title")
      "M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 0 0-2.456 2.456ZM16.894 20.567 16.5 21.75l-.394-1.183a2.25 2.25 0 0 0-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 0 0 1.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 0 0 1.423 1.423l1.183.394-1.183.394a2.25 2.25 0 0 0-1.423 1.423Z"
    when t("settings.db.title")
      "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
    else
      "M4 12h16"
    end
  end

  def widget_theme(color = "amber")
    {
      "amber"   => { border: "border-amber-200",   ring: "ring-amber-100",   label: "text-amber-700",   label_dark: "text-amber-200",   bg_accent: "bg-amber-50/50",   border_accent: "border-amber-100" },
      "violet"  => { border: "border-violet-200",  ring: "ring-violet-100",  label: "text-violet-700",  label_dark: "text-violet-200",  bg_accent: "bg-violet-50/50",  border_accent: "border-violet-100" },
      "cyan"    => { border: "border-cyan-200",    ring: "ring-cyan-100",    label: "text-cyan-700",    label_dark: "text-cyan-200",    bg_accent: "bg-cyan-50/50",    border_accent: "border-cyan-100" },
      "rose"    => { border: "border-rose-200",    ring: "ring-rose-100",    label: "text-rose-700",    label_dark: "text-rose-200",    bg_accent: "bg-rose-50/50",    border_accent: "border-rose-100" },
      "orange"  => { border: "border-orange-200",  ring: "ring-orange-100",  label: "text-orange-700",  label_dark: "text-orange-200",  bg_accent: "bg-orange-50/50",  border_accent: "border-orange-100" },
      "sky"     => { border: "border-sky-200",     ring: "ring-sky-100",     label: "text-sky-700",     label_dark: "text-sky-200",     bg_accent: "bg-sky-50/50",     border_accent: "border-sky-100" },
      "emerald" => { border: "border-emerald-200", ring: "ring-emerald-100", label: "text-emerald-700", label_dark: "text-emerald-200", bg_accent: "bg-emerald-50/50", border_accent: "border-emerald-100" },
      "indigo"  => { border: "border-indigo-200",  ring: "ring-indigo-100",  label: "text-indigo-700",  label_dark: "text-indigo-200",  bg_accent: "bg-indigo-50/50",  border_accent: "border-indigo-100" },
      "blue"    => { border: "border-blue-200",    ring: "ring-blue-100",    label: "text-blue-700",    label_dark: "text-blue-200",    bg_accent: "bg-blue-50/50",    border_accent: "border-blue-100" },
      "pink"    => { border: "border-pink-200",    ring: "ring-pink-100",    label: "text-pink-700",    label_dark: "text-pink-200",    bg_accent: "bg-pink-50/50",    border_accent: "border-pink-100" },
      "fuchsia" => { border: "border-fuchsia-200", ring: "ring-fuchsia-100", label: "text-fuchsia-700", label_dark: "text-fuchsia-200", bg_accent: "bg-fuchsia-50/50", border_accent: "border-fuchsia-100" },
      "slate"   => { border: "border-slate-200",   ring: "ring-slate-100",   label: "text-slate-700",   label_dark: "text-slate-200",   bg_accent: "bg-slate-50/50",   border_accent: "border-slate-100" }
    }[color.to_s] || widget_theme("amber")
  end

  def chart_theme(color = "violet")
    {
      "violet"  => { border: "border-violet-100",  bg: "bg-violet-50/50",  label_color: "text-violet-700",  gradient: %w[#8b5cf6 #d946ef #f9a8d4], point: "#d946ef" },
      "cyan"    => { border: "border-cyan-100",    bg: "bg-cyan-50/50",    label_color: "text-cyan-700",    gradient: %w[#06b6d4 #38bdf8 #a5f3fc], point: "#38bdf8" },
      "rose"    => { border: "border-rose-100",    bg: "bg-rose-50/50",    label_color: "text-rose-700",    gradient: %w[#ef4444 #fb7185 #fecdd3], point: "#fb7185" },
      "orange"  => { border: "border-orange-100",  bg: "bg-orange-50/50",  label_color: "text-orange-700",  gradient: %w[#f97316 #fb923c #fed7aa], point: "#fb923c" },
      "sky"     => { border: "border-sky-100",     bg: "bg-sky-50/50",     label_color: "text-sky-700",     gradient: %w[#0284c7 #38bdf8 #bae6fd], point: "#38bdf8" },
      "emerald" => { border: "border-emerald-100", bg: "bg-emerald-50/50", label_color: "text-emerald-700", gradient: %w[#10b981 #34d399 #a7f3d0], point: "#34d399" },
      "amber"   => { border: "border-amber-100",   bg: "bg-amber-50/50",  label_color: "text-amber-700",   gradient: %w[#f59e0b #fbbf24 #fde68a], point: "#fbbf24" }
    }[color.to_s] || chart_theme("violet")
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
