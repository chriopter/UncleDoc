# UncleDoc

UncleDoc is a self-hosted family health manager built in Rails. It lets you enter health data or upload documents, then chat with the resulting health record.

<img src="docs/screenshots/overview-demo-nora.png" alt="Demo Nora overview" width="60%" />

Bring your own LLM. UncleDoc does not provide medical advice and should support your record-keeping, not replace professional care.

## 1. What It Does

UncleDoc keeps a household's health information in one place and makes it usable day to day.

- **Multi-person household record**
Track multiple people in one app, each with their own history, overview, files, and trends.

- **Fast timeline logging**
Add notes, measurements, timestamps, and uploads in a single stream that stays easy to scan later.

- **Structured health record**
Notes can stay simple, or become structured facts that power charts, summaries, planning, and search.

- **Useful everyday views**
Each person gets an `Overview`, `Log`, `Trends`, `Calendar`, `Files`, `Baby`, and `HealthKit` area.

- **Baby mode**
Feeding, diaper, sleep, and growth workflows are faster when you are tracking a baby and do not want extra friction.

- **LLM-powered parsing and chat**
If you configure an LLM, UncleDoc can turn notes into structured data, summarize health history, and answer questions against the record.

- **Admin side without clutter**
Settings, raw database browsing, LLM setup, prompt preview, and logs stay available without getting in the way of normal use.

- **Bilingual UI**
The app supports both English and German via Rails I18n.

## 2. iOS App

UncleDoc also includes an iOS app so the same household health record feels at home on iPhone.

It can sync HealthKit data into UncleDoc, which means device-collected measurements can live alongside manual notes and uploaded documents.

The iOS app stays intentionally thin, with the main product experience still living in Rails.

## 3. Installation

### Requirements

- Ruby `4.0.2`
- Bundler
- SQLite3

### Local setup

```bash
bundle install
bin/rails db:prepare
bundle exec bin/rails db:seed
bin/dev
```

`db:seed` prepares demo profiles, including `Demo Nora` for the overview demo.

### Run tests

```bash
bin/rails test
```

### What `bin/dev` starts

- Rails on `0.0.0.0:3000`
- the Tailwind watcher

## 4. Details

### Stack

- Ruby `4.0.2`
- Rails `8.1`
- SQLite
- Hotwire (`turbo-rails`, `stimulus-rails`)
- Tailwind CSS
- Active Storage
- Solid Queue / Solid Cache / Solid Cable
- `ruby_llm`

### Data model

UncleDoc starts with a simple model: a person, a timeline of entries, and optional structured data layered on top.

| Model | Purpose | Main fields |
| --- | --- | --- |
| `Person` | Household member being tracked | `name`, `birth_date`, `baby_mode`, `uuid` |
| `Entry` | Main timeline item for manual logs and generated summaries | `input`, `occurred_at`, `facts`, `parseable_data`, `parse_status`, `source` |
| `UserPreference` | Saved app and LLM preferences | locale, date format, provider, model |
| `HealthkitRecord` / `HealthkitSync` | Raw imported iOS health data and sync state | source payloads, sync metadata |

### Normal data and parsing

The normal flow is deliberately simple: write a note, attach a document if needed, and let UncleDoc keep it as-is or enrich it with structure.

| Layer | What it stores | Example |
| --- | --- | --- |
| Original input | The raw note or uploaded-document context | "Fever 38.2C after lunch" |
| Facts | Short human-readable takeaways | "Temperature 38.2 C" |
| `parseable_data` | Structured machine-readable items | `{ "type": "temperature", "value": 38.2, "unit": "C" }` |

This means the app is still useful without parsing, but gets much stronger once structured data exists.

### LLM integration

LLM support is optional.

If configured, UncleDoc can:

- parse free-text notes into structured `parseable_data`
- generate summaries
- answer chat questions against a person's record
- store request/response metadata in `llm_logs`

Supported providers currently include `OpenAI`, `Fireworks`, `OpenRouter`, `Ollama`, `xAI`, `Mistral`, `Perplexity`, and `DeepSeek`.

### HealthKit compaction

HealthKit imports are stored separately first, then compacted into timeline-friendly summaries so the main log stays readable.

| Layer | Purpose | Result in UncleDoc |
| --- | --- | --- |
| `HealthkitRecord` | Keep raw imported measurements | Preserves device-origin data |
| Sync / grouping | Organize records by person and import window | Makes updates repeatable |
| Generated summary `Entry` | Turn many readings into one usable timeline item | Daily or grouped health summary |

### Demo data

The seed data builds three demo profiles:

- `Demo Nora`
- `Demo Theo`
- `Demo Mila`

`Demo Nora` is the best overview/demo profile and includes curated recent activity, planning items, and chartable measurements.

After starting the app, open:

```text
http://127.0.0.1:3000/Demo%20Nora/overview
```

### Local LAN setup

This repo is also used in a LAN-only self-hosted setup:

- app directory: `/root/uncledoc`
- service: `uncledoc-dev.service`
- command: `bin/dev`
- environment: `development`
- bind: `0.0.0.0:3000`
- persistent DB: `storage/development.sqlite3`

Useful commands:

```bash
systemctl status uncledoc-dev.service
systemctl restart uncledoc-dev.service
systemctl stop uncledoc-dev.service
journalctl -u uncledoc-dev.service -f
```

### Project notes

- All user-facing UI text should go through Rails I18n.
- New UI text must include both English and German translations.
- Web UI changes should preserve Hotwire Native iOS behavior.
- Local app data in `storage/development.sqlite3` should be treated as valuable.

## License

UncleDoc is released under the `O'Saasy` license. In practice, that means the code can be used, modified, and self-hosted, but not used to launch a competing hosted/SaaS version of UncleDoc itself. See `LICENSE`.
