# Entry Parsing

Return exactly one JSON object with these keys:

```json
{
  "facts": ["..."],
  "parseable_data": [
    { "type": "..." }
  ],
  "occurred_at": null,
  "llm_response": {
    "status": "structured",
    "confidence": "high",
    "note": "Canonical structured data extracted successfully."
  }
}
```

Rules:

- No prose or Markdown outside the JSON object.
- Facts must be short strings in the same language as the input when the input language is clear.
- The entry may include attached documents such as PDFs, invoices, lab sheets, or photos. Read the attachments directly when present and treat them like primary source input.
- Always use English canonical schema for `parseable_data`, even if the input is another language.
- Always try to return the best useful `facts` and the best useful `parseable_data` you can.
- When a document contains useful health or admin details, extract them into `facts` and `parseable_data` even if the typed note is short or empty.
- If the note is clearly machine-usable, do not leave `parseable_data` empty.
- When the note fits one of these app-critical widget types, prefer that exact canonical type: `temperature`, `pulse`, `weight`, `height`, `bottle_feeding`, `breast_feeding`, `diaper`.
- For clear measurements, feedings, diapers, medication, vaccination, appointments, todos, symptoms, or lab values, return at least one `parseable_data` item.
- Return at most one `todo` item per entry.
- Return at most one `healthkit_summary` item per entry.
- `todo` completion state is app-managed. Never encode checked/done state from the app into `parseable_data`.
- `todo` is only for actionable reminders, checks, or follow-ups.
- Medical findings, measurements, symptoms, vaccinations, medication, vitals, and similar health data are never `todo` or `appointment`.
- Individual lab markers from bloodwork, urine tests, chemistry panels, thyroid panels, vitamin checks, and similar reports are not `medication`. Use `lab_result`.
- Use `occurred_at` only when the input implies a specific event time. Otherwise return `null`.
- Prefer concrete document facts over generic descriptions like "invoice uploaded" or "report attached".
- `llm_response` must always be present with `status`, `confidence`, and `note` in English.
- When `Entry source` is `healthkit`, treat the note as a generated Apple Health summary. Always return one `healthkit_summary` item with `value: "Apple Health"` and `quality: "daily"` or `quality: "monthly"` based on the note, while also extracting obvious measurements like `weight`, `pulse`, `sleep`, or `blood_pressure` when they are present.
- For Apple Health summary entries, do not stop at `healthkit_summary` alone. Convert every quantified Apple Health bullet into the best canonical item you can:
  - `weight`, `pulse`, `sleep`, `blood_pressure`, `temperature`, `height` when they clearly fit
  - use `lab_result` for other numeric Apple Health metrics such as step count, walking distance, active energy, basal energy, flights climbed, walking speed, walking step length, HRV, respiratory rate, oxygen saturation, VO2 max, workouts, and dietary totals
- For Apple Health `lab_result` items, use the metric name as `value` and the measured number as `result`.
- Apple Health summary entries are generated data, not todos, appointments, medication, or vaccination.

Canonical types:

- `temperature`: `type`, `value`, `unit`, optional `flag`
- `pulse`: `type`, `value`, `unit`
- `weight`: `type`, `value`, `unit`
- `height`: `type`, `value`, `unit`
- `bottle_feeding`: `type`, `value`, `unit`
- `breast_feeding`: `type`, optional `value`, optional `unit`, optional `side`, optional `quality`
- `diaper`: `type`, `wet`, `solid`, optional `rash`
- `medication`: `type`, `value`, optional `dose`
- `vaccination`: `type`, `value`, optional `dose`
- `appointment`: `type`, `value`, optional `scheduled_for`, optional `location`, optional `quality`
- `todo`: `type`, `value`, optional `due_at`, optional `location`, optional `quality`
- `sleep`: `type`, `value`, `unit`
- `symptom`: `type`, `value`, optional `location`, optional `quality`
- `blood_pressure`: `type`, `systolic`, `diastolic`, optional `unit`
- `lab_result`: `type`, `value`, `result`, optional `unit`, optional `ref`, optional `flag`
- `healthkit_summary`: `type`, `value`, optional `quality`

Mapping hints:

- Map `Trinken`, `Stillen`, or `Fütterung` to `breast_feeding` unless the note clearly indicates a bottle.
- Map `Windel` to `diaper`.
- Map `Impfung` to `vaccination`.
- Map `Termin`, `doctor appointment`, or similar visit planning to `appointment`.
- Map actionable reminders, checks, and pinned follow-ups to `todo`.
- Map lab sheet rows like `Hemoglobin 15.2 g/dl`, `TSH 1.35 µIU/ml`, or `Vitamin D 81.9 ng/ml` to `lab_result`, where `value` is the marker name and `result` is the measured number or text.

Examples:

- `53cm Körpergröße` -> `facts`: `["Körpergröße 53 cm"]`; `parseable_data`: `[ { "type": "height", "value": 53, "unit": "cm" } ]`
- `sonntag RSV Impfung` -> `facts`: `["RSV-Impfung am Sonntag"]`; `parseable_data`: `[ { "type": "vaccination", "value": "RSV" } ]`
- `Doctor appointment on 5.4. at 10:30 in the hospital` -> `parseable_data`: `[ { "type": "appointment", "value": "doctor appointment", "scheduled_for": "2026-04-05T10:30:00Z", "location": "hospital" } ]`
- `todo bring vaccination card` -> `parseable_data`: `[ { "type": "todo", "value": "bring vaccination card" } ]`
- `ask about feeding amount` -> `parseable_data`: `[ { "type": "todo", "value": "ask about feeding amount", "quality": "pinned" } ]`
- `Blood pressure 120/80` -> `parseable_data`: `[ { "type": "blood_pressure", "systolic": 120, "diastolic": 80, "unit": "mmHg" } ]`
- `Hemoglobin 15.2 g/dl (13.5-17.5)` -> `parseable_data`: `[ { "type": "lab_result", "value": "Hemoglobin", "result": 15.2, "unit": "g/dl", "ref": "13.5-17.5" } ]`
- `Apple Health monthly summary for March 2026. Entry source: healthkit.` -> `parseable_data`: `[ { "type": "healthkit_summary", "value": "Apple Health", "quality": "monthly" } ]`
- `Apple Health daily summary for April 05, 2026. - Step count 3972 count. - Walking and running distance 2.78 km. - Active energy burned 150.55 kcal.` -> `parseable_data`: `[ { "type": "healthkit_summary", "value": "Apple Health", "quality": "daily" }, { "type": "lab_result", "value": "Step count", "result": 3972, "unit": "count" }, { "type": "lab_result", "value": "Walking and running distance", "result": 2.78, "unit": "km" }, { "type": "lab_result", "value": "Active energy burned", "result": 150.55, "unit": "kcal" } ]`
- `Apple Health monthly summary for March 2026. - Weight avg 97 kg; min 96.4; max 97.8. - Resting pulse avg 58 bpm; min 54; max 63.` -> `parseable_data`: `[ { "type": "healthkit_summary", "value": "Apple Health", "quality": "monthly" }, { "type": "weight", "value": 97, "unit": "kg" }, { "type": "pulse", "value": 58, "unit": "bpm" } ]`
