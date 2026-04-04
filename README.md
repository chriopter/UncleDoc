# UncleDoc

A small self-hosted family health tracker built with Rails, Hotwire, and Tailwind CSS.

## Features

- **Family Management**: Track health data for multiple family members
- **Baby Mode**: Specialized tracking for infants (feeding, diaper changes, sleep)
- **Flexible Health Data**: Extensible system for any health metric (temperature, pulse, weight, etc.)
- **Bilingual**: Full English and German support
- **Self-Hosted**: Your data stays on your server

## Data Model

Every health log entry has only two core payloads:

- `note`: the original free text from the user; this stays the source of truth
- `data`: a JSON array with structured facts parsed from the note or written directly by quick actions

Each row also stores `occurred_at`, so the timeline can sort, summarize, and chart events correctly.

Example entry payload:

```json
[
  { "type": "temperature", "value": 39.2, "unit": "C", "flag": "high" },
  { "type": "medication", "value": "ibuprofen", "dose": "400mg" }
]
```

### Two Ways Entries Are Created

1. Free text: save `note` first, then parse into `data` asynchronously via the configured LLM
2. Quick actions: write `data` directly and auto-generate a matching `note`

Both paths end in the same `entries` table and the same UI.

### Querying Structured Data

`data` is always a JSON array of objects. Common queries use the free-form `type` field, for example `temperature`, `pulse`, `diaper`, `breast_feeding`, or `bottle_feeding`.

## LLM-First Data Plan

UncleDoc is an end-user app, so the main input model is natural language. Users log freely, the LLM interprets the note, and the app maps that input into a small stable internal vocabulary.

### Core Rule

- Do not force external healthcare standards into the product flow
- Do not try to normalize everything upfront
- Do keep a fixed internal set of event types, metric keys, units, and common values
- Let the LLM map messy user input into those internal values

### What Gets Stored

- `note` for the original human note
- `data` for parsed structured values like temperature, pulse, diaper state, bottle amount, medication, or lab values
- optional LLM-generated summaries for later features

### Parser Examples

The prompt includes compact examples for both baby tracking and elderly/sick care so the output stays predictable:

```text
Peter breastfed left side for 18 minutes
[{"type":"breast_feeding","value":18,"unit":"min","side":"left"}]

Peter diaper wet and solid
[{"type":"diaper","wet":true,"solid":true}]

Peter got ibuprofen 400mg
[{"type":"medication","value":"ibuprofen","dose":"400mg"}]

Elderly patient WBC 11.2 G/L and CRP 3.1
[{"type":"WBC","value":11.2,"unit":"G/L","ref":"4.0-10.0","flag":"high"},{"type":"CRP","value":3.1}]
```

After the model responds, UncleDoc sanitizes the JSON before saving it so units, type names, and numeric values stay consistent.

### Why This Approach

- simpler than full medical standards
- stable enough for charts, reminders, and summaries
- flexible enough for messy family logging
- well suited for an LLM-driven product

### Future Option

If UncleDoc later needs export or interoperability, standards can be added as a separate mapping layer. They are not required for the core app model.

## Development

### Prerequisites

- Ruby 3.4+
- SQLite3 (or PostgreSQL for production)
- Node.js (for Tailwind CSS)

### Setup

```bash
# Clone and install dependencies
git clone <repo>
cd uncledoc
bundle install

# Setup database
bin/rails db:prepare

# Start server
bin/dev
```


### LAN Dev Server

This repository is currently set up to run on a LAN-only server with Rails in `development` mode for fast iteration.

- App directory: `/root/uncledoc`
- Service name: `uncledoc-dev.service`
- Bind address: `0.0.0.0:3000`
- Persistent database: `storage/development.sqlite3`

`Procfile.dev` starts both Rails and the Tailwind watcher. The Rails process is intentionally kept in `development` so code changes reload immediately.

### systemd Service

The server can be managed with:

```bash
systemctl status uncledoc-dev.service
systemctl restart uncledoc-dev.service
systemctl stop uncledoc-dev.service
journalctl -u uncledoc-dev.service -f
```

On boot, `systemd` starts `bin/dev`, which in turn:

- prepares the database with `bin/rails db:prepare`
- starts the Rails server on port `3000`
- starts the Tailwind watcher for live CSS rebuilds

This setup is intended for trusted LAN use only. It should not be exposed directly to the public internet.

### Running Tests

```bash
bin/rails test
```

## Deployment

See [Kamal deployment docs](https://kamal-deploy.org) for production deployment with Docker.

### Kamal on a LAN

This app can be deployed with Kamal on a trusted LAN without requesting a public TLS certificate.

- Keep `config/deploy.yml` generic and committed.
- Keep the LAN host out of git by reading it from `KAMAL_LAN_HOST` in `config/deploy.lan.yml`.
- Store the LAN host and Kamal deploy secrets in 1Password.
- Keep Kamal proxy SSL disabled for LAN-only HTTP deployment.
- First-time setup should use `bin/setup_op`.
- Regular deploys should use `bin/deploy_op`.

Tracked LAN destination file:

```yaml
servers:
  web:
    - <%= ENV.fetch("KAMAL_LAN_HOST") %>
```

Example 1Password-backed LAN secrets template:

```sh
SECRETS=$(kamal secrets fetch --adapter 1password --account my.1password.eu --from "Private/UncleDoc Production Secrets" RAILS_MASTER_KEY)
RAILS_MASTER_KEY=$(kamal secrets extract RAILS_MASTER_KEY $SECRETS)
```

Example 1Password field for the server target:

```text
op://Private/UncleDoc Production Secrets/KAMAL_LAN_HOST
```

## License

MIT License - See LICENSE file for details.
