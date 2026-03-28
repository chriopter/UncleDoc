# UncleDoc

A small self-hosted family health tracker built with Rails, Hotwire, and Tailwind CSS.

## Features

- **Family Management**: Track health data for multiple family members
- **Baby Mode**: Specialized tracking for infants (feeding, diaper changes, sleep)
- **Flexible Health Data**: Extensible system for any health metric (temperature, pulse, weight, etc.)
- **Bilingual**: Full English and German support
- **Self-Hosted**: Your data stays on your server

## Health Data Type System

UncleDoc uses a flexible YAML-based configuration system for health tracking types. You can add new health metrics without writing code!

### Configuration File

All health data types are defined in:

```
config/entry_types.yml
```

### Adding New Health Types

Simply edit `config/entry_types.yml` and add a new entry type:

```yaml
health_weight:
  icon: "scale"
  color: "slate"
  label:
    en: "Weight"
    de: "Gewicht"
  fields:
    kg:
      type: number
      label:
        en: "Weight (kg)"
        de: "Gewicht (kg)"
      min: 0
      max: 300
      step: 0.1
      required: true
    body_fat_percent:
      type: number
      min: 0
      max: 100
      required: false
```

### Supported Field Types

- **select**: Dropdown with predefined options
- **number**: Numeric input with min/max/step validation
- **boolean**: Checkbox (true/false)
- **text**: Free text input

### Entry Type Categories

- **Baby tracking**: Types prefixed with `baby_` (feeding, diaper, sleep)
- **Health metrics**: Types prefixed with `health_` (temperature, pulse, weight)
- **General**: `note` for free-form entries

### Example Types Included

| Type | Fields | Use Case |
|------|--------|----------|
| `baby_feeding` | method, amount_ml, duration_minutes | Track bottle/breast feeding |
| `baby_diaper` | consistency, rash | Track diaper changes with consistency |
| `baby_sleep` | duration_minutes, quality | Track sleep patterns |
| `health_temperature` | celsius, location | Track body temperature |
| `health_pulse` | bpm, activity | Track heart rate |
| `note` | - | Free-form text entries |

### Data Storage

Health data is stored in a PostgreSQL JSONB column (`entries.metadata`), allowing:
- Flexible schema-less storage
- Efficient querying with GIN indexes
- Easy migration of existing data
- No database migrations when adding new field types

## LLM-First Data Plan

UncleDoc is an end-user app, so the main input model is natural language. Users log freely, the LLM interprets the note, and the app maps that input into a small stable internal vocabulary.

### Core Rule

- Do not force external healthcare standards into the product flow
- Do not try to normalize everything upfront
- Do keep a fixed internal set of event types, metric keys, units, and common values
- Let the LLM map messy user input into those internal values

### What Gets Stored

- `raw_input` for the original human note
- `entry_type` for the main event like `baby_feeding`, `baby_diaper`, `temperature`, or `note`
- `metadata` for parsed structured values like `amount_ml`, `duration_minutes`, `consistency`, or `rash`
- optional LLM-generated summary or interpretation for later features

### Internal Vocabulary Examples

- event types: `baby_feeding`, `baby_diaper`, `baby_sleep`, `health_temperature`, `health_pulse`, `note`
- metric keys: `amount_ml`, `duration_minutes`, `celsius`, `bpm`
- fixed values: `bottle`, `breast`, `solids`, `mixed`, `solid`, `fluid`, `none`, `both`

### Example

```yaml
baby_feeding:
  icon: "baby-bottle"
  color: "emerald"
  label:
    en: "Feeding"
    de: "Fütterung"
  fields:
    method:
      type: select
      options:
        - value: bottle
        - value: breast
        - value: solids
        - value: mixed
    amount_ml:
      type: number
    duration_minutes:
      type: number
```

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
bin/rails db:create db:migrate

# Start server
bin/dev
```

### Running Tests

```bash
bin/rails test
```

## Deployment

See [Kamal deployment docs](https://kamal-deploy.org) for production deployment with Docker.

## License

MIT License - See LICENSE file for details.
