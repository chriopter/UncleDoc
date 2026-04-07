# UncleDoc

UncleDoc is a small self-hosted family health tracker built with Rails, Hotwire, and Tailwind CSS.

It is designed for fast everyday logging on a phone or laptop, with English and German support, simple person-based navigation, optional LLM-assisted parsing, and a thin iOS shell for native HealthKit sync.

## What The App Does

- Track multiple people in one household.
- Create timeline entries with free text, structured data, timestamps, and optional document uploads.
- Support baby-mode workflows such as feeding, diaper, and sleep tracking.
- Show person-specific overview, log, trends, calendar, files, and HealthKit pages.
- Offer admin-style settings pages for users, raw database browsing, LLM configuration, prompt preview, and LLM logs.
- Support English (`en`) and German (`de`) locales.

## Main Concepts

### People

Each `Person` is a tracked family member with:

- `name`
- `birth_date`
- optional `baby_mode`
- a stable `uuid` used by the iOS HealthKit integration

### Entries

Each `Entry` belongs to a person and stores:

- `input`: the original note text
- `occurred_at`: when the event happened
- `parseable_data`: structured JSON facts
- `facts`: short human-readable summaries derived from structured data
- `documents`: optional uploaded files via Active Storage
- `parse_status`: `pending`, `parsed`, `failed`, or `skipped`
- `source`: `manual` or `healthkit`

The app uses one entry stream for manual logs, quick baby actions, document-backed notes, and HealthKit-generated summaries.

### Structured Data

`parseable_data` is a JSON array of objects. Common item types include:

- `temperature`
- `pulse`
- `medication`
- `appointment`
- `todo`
- `breast_feeding`
- `bottle_feeding`
- `diaper`
- `sleep`

This keeps the write path flexible while still making filtering, widgets, charts, summaries, and follow-up actions possible.

### LLM Support

If LLM settings are configured, UncleDoc can:

- parse free-text entries into structured `parseable_data`
- generate log summaries
- answer chat questions against a person's log
- record request/response metadata in `llm_logs`

Supported provider settings currently include OpenAI-compatible providers such as OpenAI, Fireworks, OpenRouter, Ollama, xAI, Mistral, Perplexity, and DeepSeek.

LLM use is optional. Entries still work without it.

### HealthKit Integration

The repo includes a native iOS app in `ios/`.

- The iOS app is primarily a Hotwire Native shell around the Rails app.
- It can sync HealthKit records to Rails endpoints under `/ios/healthkit/*`.
- Synced HealthKit records are stored separately and can generate summary entries attached to a person.

## Main Screens

For a selected person, the Rails app currently exposes:

- `/overview`
- `/log`
- `/trends`
- `/calendar`
- `/files`
- `/baby`
- `/healthkit`

Global settings pages include:

- profile preferences
- users
- HealthKit admin
- LLM settings
- LLM prompt preview
- LLM logs
- raw database browsing

## Stack

- Ruby `4.0.2`
- Rails `8.1`
- SQLite for the current local setup
- Hotwire (`turbo-rails`, `stimulus-rails`)
- Tailwind CSS
- Active Storage for uploaded documents
- Solid Queue / Solid Cache / Solid Cable
- `ruby_llm` for LLM requests

## Development Setup

### Prerequisites

- Ruby `4.0.2`
- Bundler
- SQLite3
- Node.js is not required separately when using `tailwindcss-rails`, but a normal Rails dev environment is assumed

### Install

```bash
bundle install
bin/rails db:prepare
```

### Run The App

```bash
bin/dev
```

`Procfile.dev` starts:

- Rails on `0.0.0.0:3000`
- the Tailwind watcher

### Tests

```bash
bin/rails test
```

## Local LAN Service Setup

This repo is also used in a LAN-only environment that behaves like a small self-hosted deployment.

- app directory: `/root/uncledoc`
- service name: `uncledoc-dev.service`
- command: `bin/dev`
- Rails environment: `development`
- bind address: `0.0.0.0:3000`
- persistent database: `storage/development.sqlite3`

Useful commands:

```bash
systemctl status uncledoc-dev.service
systemctl restart uncledoc-dev.service
systemctl stop uncledoc-dev.service
journalctl -u uncledoc-dev.service -f
```

This setup is intended for trusted LAN use. Do not expose it directly to the public internet.

## Deployment

The repo includes Kamal for container-based deployment.

For the current LAN-oriented workflow:

- keep generic Kamal config in git
- keep machine-specific LAN host values out of git
- store deploy secrets securely
- prefer the documented local helper scripts when present

## Repo Notes

- Web UI changes should preserve the Hotwire Native iOS shell behavior.
- All user-facing UI text should use Rails I18n and include both English and German translations.
- Local app data in `storage/development.sqlite3` should be treated as valuable.

## License

MIT. See `LICENSE`.
