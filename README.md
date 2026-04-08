<p align="center">
  <img src="assets/icons/web/icon-512.png" alt="UncleDoc logo" width="120" />
</p>

<h1 align="center">UncleDoc</h1>

<p align="center">
  <strong>Your family's health record — self-hosted, LLM-powered, fully yours.</strong><br/>
  Enter notes, upload documents, track appointments and workouts.<br/>
  UncleDoc builds a living health record you can chat with via your own LLM.
</p>

<p align="center">
  <img src="docs/screenshots/overview-demo-nora.png" alt="UncleDoc overview" width="80%" />
</p>

> UncleDoc is a self-hosted record-keeping tool, not a medical device. It does not provide medical advice, diagnosis, or treatment, and should support your documentation rather than replace professional care. 
> All information processing that leads to suggestion is done by an LLM you provide (Bring your own LLM.).
> Also, this app is heavily vibe-coded and iteration speed is currently prioritized above all else, including security. Be careful to only run this locally / in your secured LAN.

## 1. Features

- Multi-person health records
- Fast timeline logging with file uploads
- Optional LLM parsing for notes, appointments, to-dos, and document content
- Baby mode for feeding, diapers, sleep, and growth
- HealthKit sync through the iOS app

**Key principe** is to enter data (e.g. a note, a uploaded PDF) that will then be parsed by your LLM to be condensed to key facts. The resulting health record (sum of all "facts") is what you can then chat with.

## 2. iOS App

UncleDoc also includes an iOS app so the same household health record feels at home on iPhone.
It can sync HealthKit data into UncleDoc, so measurements collected on your device can live alongside manual notes and uploaded documents.
The app stays intentionally thin, with the main product experience and your data remaining on your own UncleDoc server.

## 3. Installation

### Local dev

```bash
bin/dev
```

If you want demo content, run `bundle exec bin/rails db:prepare db:seed` first.

### Deploy

```bash
kamal setup
kamal deploy
```

## 4. Details

<details>
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
<summary>Data model</summary>

UncleDoc starts with a simple model: a person, a timeline of entries, and optional structured data layered on top.

| Model | Purpose | Main fields |
| --- | --- | --- |
| `Person` | Household member being tracked | `name`, `birth_date`, `baby_mode`, `uuid` |
| `Entry` | Main timeline item for manual logs and generated summaries | `input`, `occurred_at`, `facts`, `parseable_data`, `parse_status`, `source` |
| `UserPreference` | Saved app and LLM preferences | locale, date format, provider, model |
| `HealthkitRecord` / `HealthkitSync` | Raw imported iOS health data and sync state | source payloads, sync metadata |

</details>

<details>
<summary>Normal data and parsing</summary>

The normal flow is deliberately simple: write a note, attach a document if needed, and let UncleDoc keep it as-is or enrich it with structure.

| Layer | What it stores | Example |
| --- | --- | --- |
| Original input | The raw note or uploaded-document context | "Fever 38.2C after lunch" |
| Facts | Short human-readable takeaways | "Temperature 38.2 C" |
| `parseable_data` | Structured machine-readable items | `{ "type": "temperature", "value": 38.2, "unit": "C" }` |

This means the app is still useful without parsing, but gets much stronger once structured data exists.

</details>

<details>
<summary>LLM integration</summary>

LLM support is optional.

If configured, UncleDoc can:

- parse free-text notes into structured `parseable_data`
- generate summaries
- answer chat questions against a person's record
- store request/response metadata in `llm_logs`

Supported providers currently include `OpenAI`, `Fireworks`, `OpenRouter`, `Ollama`, `xAI`, `Mistral`, `Perplexity`, and `DeepSeek`.

</details>

<details>
<summary>HealthKit compaction</summary>

HealthKit imports are stored separately first, then compacted into timeline-friendly summaries so the main log stays readable.

| Layer | Purpose | Result in UncleDoc |
| --- | --- | --- |
| `HealthkitRecord` | Keep raw imported measurements | Preserves device-origin data |
| Sync / grouping | Organize records by person and import window | Makes updates repeatable |
| Generated summary `Entry` | Turn many readings into one usable timeline item | Daily or grouped health summary |

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

<details>
<summary>Local LAN setup</summary>

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
<summary>Project notes</summary>

- All user-facing UI text should go through Rails I18n.
- New UI text must include both English and German translations.
- Web UI changes should preserve Hotwire Native iOS behavior.
- Local app data in `storage/development.sqlite3` should be treated as valuable.

</details>

## Privacy

UncleDoc does not collect user data for its own service. The app is self-hosted, so your health data stays on infrastructure you control, and there is no central UncleDoc cloud.

If you enable AI features, you choose the LLM provider yourself. Any data sent to an LLM depends on the provider and configuration you decide to use.

## License

UncleDoc is released under the `O'Saasy` license. In practice, that means the code can be used, modified, and self-hosted, but not used to launch a competing hosted/SaaS version of UncleDoc itself. See [`LICENSE`](LICENSE).
