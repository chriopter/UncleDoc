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

## Free Standards

UncleDoc can stay flexible at the UI level while still using free health-data standards where they help with consistency, exports, and future interoperability.

### What To Use For What

| Standard | Use it for | Free to use | Notes |
|---|---|---:|---|
| `FHIR` | Overall record structure and export/import shape | Yes | Best fit for future interoperability and API design |
| `LOINC` | Identifying measurable observations | Yes | Good for temperature, pulse, weight, glucose, blood pressure |
| `UCUM` | Units | Yes | Good for `kg`, `cm`, `Cel`, `mm[Hg]`, `beats/min` |

### Recommended Rule Of Thumb

- Use internal UncleDoc keys for family-care events like `baby_diaper`, `baby_feeding`, and `note`
- Use `LOINC` + `UCUM` for real measurements like temperature, pulse, weight, blood glucose, and blood pressure
- Use `FHIR` as the export/import structure later, not as the day-to-day form definition layer

### Example

```yaml
health_temperature:
  icon: "thermometer"
  color: "red"
  label:
    en: "Temperature"
    de: "Temperatur"
  standard:
    fhir_resource: "Observation"
    code_system: "LOINC"
    code: "8310-5"
  fields:
    celsius:
      type: number
      unit: "Cel"
      unit_system: "UCUM"
      required: true
```

### What Not To Force

- Do not block custom family workflows on finding a formal code first
- Do not require every baby-care event to have a standards mapping
- Keep standards as optional metadata for custom events, but make them first-class for common measurements

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
