# UncleDoc

UncleDoc is a self-hosted family health manager in Rails.

You can log health data or upload health documents. An LLM will parse them and save them in a compact manner.
Based on that data, a health record is built you can chat with.

UncleDoc is just the app, you can bring any LLM you like.

![Demo Nora overview](docs/screenshots/overview-demo-nora.png)

## 1. What It Does


<details open>
<summary>Overview</summary>

- Track multiple people in one household.
- Add timeline entries with free text, structured facts, timestamps, and optional file uploads.
- Browse a person-specific `Overview`, `Log`, `Trends`, `Calendar`, `Files`, `Baby`, and `HealthKit` area.
- Use a separate settings/admin area for users, preferences, raw DB browsing, LLM setup, prompt preview, and logs.
- Support both English and German via Rails I18n.

</details>

<details>
<summary>Core data model</summary>

- `Person`: name, birth date, optional baby mode, stable UUID for iOS sync.
- `Entry`: original input, occurred time, parsed JSON data, generated facts, parse status, source, optional documents.
- `UserPreference`: locale, date format, LLM provider, model, encrypted API key.
- `HealthkitRecord` / `HealthkitSync`: raw HealthKit import state and records from the iOS app.

</details>

<details>
<summary>Demo data</summary>

The seed data builds three demo profiles:

- `Demo Nora`
- `Demo Theo`
- `Demo Mila`

`Demo Nora` is the best overview/demo profile and includes curated recent activity, planning items, and chartable measurements.

After starting the app, open:

```text
http://127.0.0.1:3000/Demo%20Nora/overview
```

</details>

## 2. iOS App

<details open>
<summary>What is in the repo</summary>

The repo includes a native iOS app in `ios/UncleDoc.xcodeproj`.

- It is primarily a Hotwire Native shell around the Rails app.
- Product UI should stay in Rails unless the feature is truly device-specific.
- iOS-specific behavior is mainly for native onboarding and HealthKit sync.

</details>

<details>
<summary>HealthKit integration</summary>

Rails exposes HealthKit endpoints under `/ios/healthkit/*`.

- `GET /ios/healthkit/people`
- `GET /ios/healthkit/status`
- `POST /ios/healthkit/sync`
- `DELETE|POST /ios/healthkit/reset`

Imported HealthKit data is stored separately from manual entries and can generate summary entries for a person.

</details>

## 3. LLM Integration

<details open>
<summary>What it is used for</summary>

If configured, UncleDoc can:

- parse free-text notes into structured `parseable_data`
- generate log summaries
- answer chat questions against a person's log
- store request/response metadata in `llm_logs`

LLM use is optional. The app still works without it.

</details>

<details>
<summary>Supported providers</summary>

Current settings support OpenAI-compatible providers including:

- OpenAI
- Fireworks
- OpenRouter
- Ollama
- xAI
- Mistral
- Perplexity
- DeepSeek

Provider, model, and API key are managed from the settings UI.

</details>

<details>
<summary>Structured entry model</summary>

Structured entry items live in `parseable_data`, a JSON array of objects.

Common item types include:

- `temperature`
- `pulse`
- `blood_pressure`
- `weight`
- `height`
- `medication`
- `appointment`
- `todo`
- `breast_feeding`
- `bottle_feeding`
- `diaper`
- `sleep`

</details>

## 4. Installation

<details open>
<summary>Requirements</summary>

- Ruby `4.0.2`
- Bundler
- SQLite3

</details>

<details open>
<summary>Local setup</summary>

```bash
bundle install
bin/rails db:prepare
bundle exec bin/rails db:seed
bin/dev
```

`db:seed` prepares the demo profiles, including `Demo Nora` for the overview demo.

</details>

<details>
<summary>Run tests</summary>

```bash
bin/rails test
```

</details>

<details>
<summary>What <code>bin/dev</code> starts</summary>

`Procfile.dev` runs:

- Rails on `0.0.0.0:3000`
- the Tailwind watcher

</details>

## 5. Details

<details open>
<summary>Stack</summary>

- Ruby `4.0.2`
- Rails `8.1`
- SQLite
- Hotwire (`turbo-rails`, `stimulus-rails`)
- Tailwind CSS
- Active Storage
- Solid Queue / Solid Cache / Solid Cable
- `ruby_llm`

</details>

<details>
<summary>Local LAN service setup</summary>

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

</details>

<details>
<summary>Repo rules worth knowing</summary>

- All user-facing UI text should go through Rails I18n.
- New UI text must include both English and German translations.
- Web UI changes should preserve Hotwire Native iOS behavior.
- Local app data in `storage/development.sqlite3` should be treated as valuable.

</details>

## License

UncleDoc is released under the `O'Saasy` license. In practice, that means the code can be used, modified, and self-hosted, but not used to launch a competing hosted/SaaS version of UncleDoc itself. See `LICENSE`.
