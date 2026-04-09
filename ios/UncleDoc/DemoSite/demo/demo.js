(function() {
  const PRIMARY_PERSON_NAME = "Demo Nora";
  const PRIMARY_PERSON_SLUG = "Demo Nora";
  const STORAGE_KEY = "uncledoc.demo.state.v3";

  window.UncleDocDemo = {
    receiveNativeMessage: receiveNativeMessage
  };

  document.addEventListener("DOMContentLoaded", function() {
    seedDemoState();
    repairBrokenEncoding();
    normalizeSingleUserChrome();
    removePermissionWarnings();
    wireDropdowns();
    wireDisabledForms();
    setupDemoComposer();
    injectCalendarSamples();
    injectResearchPlaceholder();
    injectHealthDemoPanel();
    renderStoredEntries();
  });

  function wireDropdowns() {
    document.querySelectorAll('[data-controller="dropdown"]').forEach(function(container) {
      const button = container.querySelector('[data-action="dropdown#toggle"]');
      const menu = container.querySelector('[data-dropdown-target="menu"]');
      if (!button || !menu) return;

      button.addEventListener("click", function(event) {
        event.preventDefault();
        event.stopPropagation();
        closeOtherMenus(menu);
        menu.classList.toggle("hidden");
      });
    });

    document.addEventListener("click", function(event) {
      document.querySelectorAll('[data-dropdown-target="menu"]').forEach(function(menu) {
        if (!menu.closest('[data-controller="dropdown"]')?.contains(event.target)) {
          menu.classList.add("hidden");
        }
      });
    });
  }

  function closeOtherMenus(activeMenu) {
    document.querySelectorAll('[data-dropdown-target="menu"]').forEach(function(menu) {
      if (menu !== activeMenu) menu.classList.add("hidden");
    });
  }

  function wireDisabledForms() {
    document.querySelectorAll('form[data-demo-disabled="true"]').forEach(function(form) {
      form.addEventListener("submit", function(event) {
        if (form.matches("#entry_form form")) {
          return;
        }
        event.preventDefault();
      });
    });
  }

  function normalizeSingleUserChrome() {
    const pagePill = document.querySelector(".uncledoc-demo-pill");
    if (pagePill) pagePill.textContent = demoPageLabel();

    document.querySelectorAll('[aria-label="Family"]').forEach(function(button) {
      const container = button.closest('[data-controller="dropdown"]');
      container?.removeAttribute("data-controller");
      container?.querySelector('[data-dropdown-target="menu"]')?.remove();
      button.querySelectorAll("svg").forEach(function(svg, index, all) {
        if (index === all.length - 1) svg.remove();
      });
      const title = button.querySelector("span.truncate");
      if (title) title.textContent = PRIMARY_PERSON_NAME;
    });

    document.querySelectorAll('aside [data-controller="dropdown"]').forEach(function(container) {
      const button = container.querySelector('button.group.mx-auto');
      if (!button) return;
      container.removeAttribute("data-controller");
      container.querySelector('[data-dropdown-target="menu"]')?.remove();
      button.querySelectorAll("svg").forEach(function(svg) { svg.remove(); });
      const title = button.querySelector("h1");
      if (title) title.textContent = PRIMARY_PERSON_NAME;
    });

    document.querySelectorAll("p, span, h1").forEach(function(node) {
      const text = (node.textContent || "").trim();
      if (text === "Test User") {
        node.textContent = PRIMARY_PERSON_NAME;
      }
      if (text.includes("@")) {
        node.textContent = "Offline sample";
      }
    });

    document.querySelectorAll("p.truncate.text-sm.font-semibold.text-slate-900").forEach(function(node) {
      node.textContent = PRIMARY_PERSON_NAME;
    });

    document.querySelectorAll("form.button_to").forEach(function(form) {
      const label = form.textContent || "";
      if (label.includes("Sign out")) {
        form.closest("div.mt-2.border-t")?.remove();
        form.closest("form")?.remove();
      }
    });

    document.querySelectorAll('a[href*="Test%20User"], a[href*="Demo%20Mila"], a[href*="Demo%20Theo"]').forEach(function(link) {
      const wrapper = link.closest("a") || link;
      wrapper.remove();
    });
  }

  function repairBrokenEncoding() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const textNodes = [];
    while (walker.nextNode()) {
      textNodes.push(walker.currentNode);
    }

    textNodes.forEach(function(node) {
      node.textContent = repairText(node.textContent);
    });

    document.querySelectorAll("[placeholder], [title], [aria-label]").forEach(function(node) {
      ["placeholder", "title", "aria-label"].forEach(function(attribute) {
        if (node.hasAttribute(attribute)) {
          node.setAttribute(attribute, repairText(node.getAttribute(attribute)));
        }
      });
    });
  }

  function repairText(value) {
    if (!value || !/[ÃÂâ]/.test(value)) {
      return value;
    }

    try {
      return decodeURIComponent(escape(value));
    } catch (_error) {
      return value;
    }
  }

  function removePermissionWarnings() {
    document.querySelectorAll("div, p, section").forEach(function(node) {
      const text = (node.textContent || "").trim();
      if (text.includes("permission to access") || text.includes("access that area")) {
        node.remove();
      }
    });
  }

  function setupDemoComposer() {
    document.querySelectorAll("#entry_form form").forEach(function(form) {
      form.dataset.demoComposer = "true";
      form.removeAttribute("data-demo-disabled");
      form.removeAttribute("onsubmit");
      form.querySelectorAll("[data-demo-disabled-control]").forEach(function(control) {
        control.removeAttribute("data-demo-disabled-control");
      });

      const toggleButton = form.querySelector('[data-action="entry-composer#toggleTime"]');
      const timeFields = form.querySelector('[data-entry-composer-target="timeFields"]');
      if (toggleButton && timeFields) {
        toggleButton.addEventListener("click", function(event) {
          event.preventDefault();
          timeFields.classList.toggle("hidden");
        });
      }

      const attachButton = form.querySelector('[data-action="entry-composer#openFilePicker"]');
      if (attachButton) {
        attachButton.addEventListener("click", function(event) {
          event.preventDefault();
          showComposerHint(form, "Attachments stay disabled in offline demo mode.");
        });
      }

      form.addEventListener("submit", function(event) {
        event.preventDefault();
        submitDemoEntry(form);
      });
    });
  }

  function submitDemoEntry(form) {
    const input = form.querySelector('textarea[name="entry[input]"]');
    const occurredAtInput = form.querySelector('input[name="entry[occurred_at]"]');
    const value = (input?.value || "").trim();
    if (!value) {
      showComposerHint(form, "Add a short note first.");
      return;
    }

    const state = loadDemoState();
    state.manualEntries.unshift({
      id: demoID(),
      title: value.length > 72 ? value.slice(0, 72) + "…" : value,
      detail: value,
      occurredAt: occurredAtInput?.value ? new Date(occurredAtInput.value).toISOString() : new Date().toISOString(),
      source: "Manual",
      kind: "manual"
    });
    saveDemoState(state);

    input.value = "";
    showComposerHint(form, "Saved to the offline demo protocol.");
    renderStoredEntries();
  }

  function showComposerHint(form, message) {
    const hint = form.querySelector('[data-entry-composer-target="files"]');
    if (hint) {
      hint.textContent = message;
    }
  }

  function injectHealthDemoPanel() {
    const path = demoPath();
    if (!path.endsWith("/healthkit")) return;

    const pageHeader = document.querySelector("section.space-y-5") || document.querySelector("main");
    if (!pageHeader) return;

    const panel = document.createElement("section");
    panel.className = "uncledoc-demo-panel";
    panel.innerHTML = [
      "<h2>Demo Health access</h2>",
      "<p>Ask iOS for Health access, then load recent records into the offline demo.</p>",
      '<div class="uncledoc-demo-actions"><button type="button" id="uncledoc-demo-health-button">Allow Health access</button></div>',
      '<div class="uncledoc-demo-note" id="uncledoc-demo-sync-note">No HealthKit records loaded yet.</div>',
      '<div class="mt-4 space-y-3" id="uncledoc-demo-health-records"></div>'
    ].join("");
    pageHeader.insertBefore(panel, pageHeader.children[1] || null);

    const button = panel.querySelector("#uncledoc-demo-health-button");
    const note = panel.querySelector("#uncledoc-demo-sync-note");
    const recordsContainer = panel.querySelector("#uncledoc-demo-health-records");
    renderHealthNote(note, loadDemoState().healthRecords);
    renderHealthRecords(recordsContainer, loadDemoState().healthRecords);

    button.addEventListener("click", function() {
      button.disabled = true;
      note.textContent = "Waiting for iOS Health permissions…";
      postNativeMessage({ type: "requestHealthAccess" });
    });
  }

  function injectCalendarSamples() {
    if (!demoPath().endsWith("/calendar")) return;

    const cells = Array.from(document.querySelectorAll("#calendar-grid .grid.grid-cols-7 > div"))
      .filter(function(cell) { return !cell.className.includes("opacity-20"); })
      .slice(8, 14);
    if (!cells.length) return;

    const samples = [
      "Pediatric follow-up 09:30",
      "Bring vaccination card",
      "School nurse note review"
    ];

    samples.forEach(function(sample, index) {
      const cell = cells[index * 2] || cells[index] || cells[0];
      if (!cell || cell.querySelector('[data-demo-calendar="true"]')) return;
      const block = document.createElement("div");
      block.dataset.demoCalendar = "true";
      block.className = "mt-1 truncate rounded-md bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-900";
      block.textContent = sample;
      cell.appendChild(block);
    });
  }

  function injectResearchPlaceholder() {
    if (!demoPath().endsWith("/research")) return;

    const panel = document.querySelector("section.flex.w-full.flex-col.rounded-\[2rem\]");
    if (panel) {
      panel.className = "w-full rounded-[2rem] border border-slate-200 bg-white ring-1 ring-black/5";
      panel.innerHTML = [
        '<div class="border-b border-slate-200 px-5 py-4">',
        '<div class="flex items-center gap-3">',
        '<div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-amber-100 text-sm font-black text-amber-800 ring-1 ring-amber-200/80">D</div>',
        '<div>',
        '<h2 class="text-base font-bold text-slate-950">Demo Nora Research</h2>',
        '<p class="text-xs text-slate-500">Research requires your own LLM configuration</p>',
        '</div>',
        '</div>',
        '</div>',
        '<div class="space-y-5 px-5 py-5">',
        '<div class="rounded-[1.75rem] border border-slate-200 bg-slate-50 px-5 py-6 text-center">',
        '<p class="text-sm font-semibold text-slate-900">Research needs your own LLM</p>',
        '<p class="mt-2 text-sm text-slate-500">Configure your own LLM on your server to use Research in the live app.</p>',
        '</div>',
        '<div class="rounded-[1.75rem] border border-slate-200 bg-white px-4 py-4 opacity-70">',
        '<div class="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-400">Ask a question about the patient record...</div>',
        '<div class="mt-3 flex justify-end"><button type="button" disabled class="rounded-full bg-slate-300 px-4 py-2 text-sm font-semibold text-white">Send</button></div>',
        '</div>',
        '</div>'
      ].join("");
    }
  }

  function renderStoredEntries() {
    renderOverviewEntries();
    renderProtocolEntries();
  }

  function renderOverviewEntries() {
    const card = document.querySelector("#overview_recent_activity");
    if (!card) return;

    card.querySelectorAll("[data-demo-entry='true']").forEach(function(node) { node.remove(); });
    const entries = storedEntries();
    if (!entries.length) return;

    const container = card.querySelector(".space-y-0") || createOverviewList(card);
    entries.slice(0, 5).reverse().forEach(function(entry) {
      container.insertAdjacentHTML("afterbegin", compactEntryMarkup(entry));
    });
  }

  function renderProtocolEntries() {
    const frame = document.querySelector("#entries_list");
    if (!frame) return;

    frame.querySelectorAll("[data-demo-entry='true']").forEach(function(node) { node.remove(); });
    const list = frame.querySelector(":scope > div") || frame;
    const entries = storedEntries();
    if (!entries.length) return;

    entries.slice().reverse().forEach(function(entry) {
      list.insertAdjacentHTML("afterbegin", protocolEntryMarkup(entry));
    });
    updateProtocolCount(entries.length);
  }

  function createOverviewList(card) {
    const empty = card.querySelector("p.py-6.text-center.text-sm.text-slate-400");
    empty?.remove();
    const list = document.createElement("div");
    list.className = "space-y-0";
    card.appendChild(list);
    return list;
  }

  function updateProtocolCount(extraEntries) {
    const badge = document.querySelector("#log_header .rounded-full.border.border-amber-200");
    if (!badge) return;
    if (!badge.dataset.baseCount) {
      const match = badge.textContent.match(/\d+/);
      badge.dataset.baseCount = String(match ? Number(match[0]) : 0);
    }
    const baseCount = Number(badge.dataset.baseCount || 0);
    badge.textContent = (baseCount + extraEntries) + " entries";
  }

  function storedEntries() {
    const state = loadDemoState();
    return state.manualEntries.concat(state.healthEntries).sort(function(a, b) {
      return new Date(b.occurredAt).getTime() - new Date(a.occurredAt).getTime();
    });
  }

  function renderHealthNote(element, records) {
    if (!element) return;
    if (!records || !records.length) {
      element.textContent = "No HealthKit records loaded yet.";
      return;
    }

    const latest = new Date(records[0].startDate).toLocaleString();
    element.textContent = "Loaded " + records.length + " recent HealthKit records. Latest sample: " + latest + ".";
  }

  function renderHealthRecords(container, records) {
    if (!container) return;
    container.innerHTML = "";
    (records || []).slice(0, 8).forEach(function(record) {
      const row = document.createElement("div");
      row.className = "rounded-2xl border border-slate-200 bg-white/85 px-4 py-3";
      row.innerHTML = [
        '<div class="flex items-start justify-between gap-3">',
        '<p class="text-sm font-semibold text-slate-900">' + escapeHTML(record.title) + '</p>',
        '<span class="rounded-full bg-rose-100 px-2 py-0.5 text-[10px] font-semibold text-rose-700">Health</span>',
        '</div>',
        '<p class="mt-1 text-xs text-slate-500">' + escapeHTML(formatDate(record.startDate)) + '</p>',
        '<p class="mt-2 text-sm text-slate-600 whitespace-pre-wrap">' + escapeHTML(record.rawText) + '</p>'
      ].join("");
      container.appendChild(row);
    });
  }

  function receiveNativeMessage(payload) {
    if (!payload || !payload.type) return;

    if (payload.type === "healthkitRecords") {
      const state = loadDemoState();
      state.healthRecords = payload.records || [];
      state.healthEntries = state.healthRecords.map(function(record) {
        return {
          id: demoID(),
          title: record.title,
          detail: record.rawText,
          occurredAt: record.startDate,
          source: "HealthKit",
          kind: "health"
        };
      });
      saveDemoState(state);
      renderHealthNote(document.querySelector("#uncledoc-demo-sync-note"), state.healthRecords);
      renderHealthRecords(document.querySelector("#uncledoc-demo-health-records"), state.healthRecords);
      renderStoredEntries();
      enableHealthButton();
      return;
    }

    if (payload.type === "healthkitError") {
      const note = document.querySelector("#uncledoc-demo-sync-note");
      if (note) note.textContent = payload.message || "HealthKit demo failed.";
      enableHealthButton();
    }
  }

  function enableHealthButton() {
    const button = document.querySelector("#uncledoc-demo-health-button");
    if (button) button.disabled = false;
  }

  function postNativeMessage(payload) {
    const handler = window.webkit?.messageHandlers?.uncledocDemo;
    if (!handler) {
      const note = document.querySelector("#uncledoc-demo-sync-note");
      if (note) note.textContent = "Native HealthKit bridge unavailable in this build.";
      enableHealthButton();
      return;
    }
    handler.postMessage(payload);
  }

  function demoPath() {
    return document.body?.dataset?.demoPath || window.location.pathname || "/";
  }

  function loadDemoState() {
    try {
      return Object.assign(defaultDemoState(), JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "{}"));
    } catch (_error) {
      return defaultDemoState();
    }
  }

  function saveDemoState(state) {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  function seedDemoState() {
    const existing = window.localStorage.getItem(STORAGE_KEY);
    if (existing) return;
    saveDemoState(defaultDemoState());
  }

  function defaultDemoState() {
    return {
      manualEntries: [
        {
          id: "demo-default-1",
          title: "Morning temperature 36.8C, pulse 76 bpm",
          detail: "Morning check before school. Temperature 36.8C, pulse 76 bpm, mood good, breakfast finished.",
          occurredAt: "2026-04-09T07:40:00Z",
          source: "Manual",
          kind: "manual"
        },
        {
          id: "demo-default-2",
          title: "After-school blood pressure 118/76",
          detail: "After school check after a long walk. Blood pressure 118/76, no dizziness, hydration okay.",
          occurredAt: "2026-04-09T16:50:00Z",
          source: "Manual",
          kind: "manual"
        },
        {
          id: "demo-default-3",
          title: "Temperature 37.0C, pulse 82 bpm",
          detail: "Mild headache around lunch. Temperature 37.0C, pulse 82 bpm, ibuprofen 200mg given with food.",
          occurredAt: "2026-04-08T12:15:00Z",
          source: "Manual",
          kind: "manual"
        },
        {
          id: "demo-default-4",
          title: "Weight check 29.4 kg",
          detail: "Weekly weight check entered in the family log. Weight 29.4 kg.",
          occurredAt: "2026-04-06T08:10:00Z",
          source: "Manual",
          kind: "manual"
        }
      ],
      healthEntries: [],
      healthRecords: []
    };
  }

  function compactEntryMarkup(entry) {
    return [
      '<details class="group border-b border-slate-100 last:border-0" data-demo-entry="true">',
      '<summary class="flex cursor-pointer items-start gap-3 rounded-2xl px-3 py-3 transition hover:bg-amber-50/70">',
      '<div class="w-20 flex-shrink-0 text-[11px] text-slate-500">',
      '<div>' + escapeHTML(formatShortDate(entry.occurredAt)) + '</div>',
      '<div class="mt-0.5 text-[10px] text-slate-400">' + escapeHTML(formatShortTime(entry.occurredAt)) + '</div>',
      '</div>',
      '<div class="flex-1 min-w-0">',
      '<div class="mb-1 flex items-start gap-2">',
      '<p class="line-clamp-6 min-w-0 flex-1 break-words text-sm font-medium leading-snug text-slate-900 [overflow-wrap:anywhere]">' + escapeHTML(entry.title) + '</p>',
      sourceBadge(entry),
      '</div>',
      '</div>',
      '<div class="flex h-7 w-7 items-center justify-center rounded-full border border-slate-200 bg-white text-slate-500 shadow-sm transition group-open:rotate-180">',
      '<svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5"></path></svg>',
      '</div>',
      '</summary>',
      '<div class="px-3 pb-3 pt-1">',
      '<div class="rounded-2xl border border-slate-200 bg-slate-50 p-4 overflow-hidden break-all">',
      '<p class="mb-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">Input</p>',
      '<p class="whitespace-pre-wrap break-words text-sm leading-relaxed text-slate-700 [overflow-wrap:anywhere]">' + escapeHTML(entry.detail) + '</p>',
      '</div>',
      '</div>',
      '</details>'
    ].join("");
  }

  function protocolEntryMarkup(entry) {
    return [
      '<div class="uncledoc-demo-entry" data-demo-entry="true">',
      '<details class="group" open>',
      '<summary>',
      '<div class="shrink-0 text-right"><p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-amber-700">' + escapeHTML(formatLongDay(entry.occurredAt)) + '</p></div>',
      '<p class="min-w-0 truncate text-sm"><span class="text-slate-800">' + escapeHTML(entry.title) + '</span></p>',
      '<div class="flex justify-end">' + protocolSourceBadge(entry) + '</div>',
      '<div class="flex justify-end"></div>',
      '<div class="flex justify-end"></div>',
      '<svg class="h-3.5 w-3.5 shrink-0 text-slate-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5"></path></svg>',
      '</summary>',
      '<div class="uncledoc-demo-entry-body">',
      '<p class="text-xs text-slate-400">' + escapeHTML(formatDate(entry.occurredAt)) + '</p>',
      '<div class="mt-3 space-y-3"><p class="text-sm leading-relaxed text-slate-700 whitespace-pre-wrap">' + escapeHTML(entry.detail) + '</p></div>',
      '</div>',
      '</details>',
      '</div>'
    ].join("");
  }

  function sourceBadge(entry) {
    if (entry.kind === "health") {
      return '<span class="inline-flex shrink-0 rounded-full bg-rose-100 px-2.5 py-1 text-[10px] font-semibold leading-none text-rose-600">Health</span>';
    }
    return '<span class="inline-flex shrink-0 rounded-full bg-amber-100 px-2.5 py-1 text-[10px] font-semibold leading-none text-amber-700">Manual</span>';
  }

  function protocolSourceBadge(entry) {
    if (entry.kind === "health") {
      return '<span class="rounded-full bg-rose-100 px-2.5 py-1 text-[10px] font-semibold leading-none text-rose-600">Health</span>';
    }
    return '<span class="rounded-full bg-amber-100 px-2.5 py-1 text-[10px] font-semibold leading-none text-amber-700">Manual</span>';
  }

  function formatDate(value) {
    return new Date(value).toLocaleString();
  }

  function formatShortDate(value) {
    const date = new Date(value);
    return String(date.getMonth() + 1).padStart(2, "0") + "/" + String(date.getDate()).padStart(2, "0");
  }

  function formatShortTime(value) {
    const date = new Date(value);
    return String(date.getHours()).padStart(2, "0") + ":" + String(date.getMinutes()).padStart(2, "0");
  }

  function formatLongDay(value) {
    return new Date(value).toLocaleDateString(undefined, { month: "long", day: "numeric" });
  }

  function escapeHTML(value) {
    const div = document.createElement("div");
    div.textContent = value || "";
    return div.innerHTML;
  }

  function demoID() {
    return (window.crypto?.randomUUID && window.crypto.randomUUID()) || String(Date.now()) + String(Math.random()).slice(2);
  }

  function demoPageLabel() {
    const path = demoPath().toLowerCase();
    if (path.includes("/overview")) return "Overview";
    if (path.includes("/log")) return "Log";
    if (path.includes("/healthkit")) return "HealthKit";
    if (path.includes("/calendar")) return "Calendar";
    if (path.includes("/research")) return "Research";
    if (path.includes("/files")) return "Files";
    return "Demo";
  }
})();
