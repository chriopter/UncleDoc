# AGENTS

## Stack Rules

- Build everything in Rails.
- Use Hotwire for interactivity.
- Use Tailwind CSS for styling.
- Keep v1 aggressively simple and mobile-first.
- **All UI text must be dual-language (English/German) using Rails I18n.**

## Product Direction

- UncleDoc v1 starts as a tiny family health tracker.
- First milestone is only `Person` records with `name` and `birth_date`.
- The main web UI has two tabs: `Log` and `DB`.
- `Log` is the friendly app view.
- `DB` is an admin-style raw database view.
- **Support English (en) and German (de) locales. All new features must include translations for both languages in `config/locales/`.**

## Delivery Style

- Prefer small controllers, simple ERB views, and plain Rails conventions.
- Avoid extra gems unless Rails already ships the capability.
- Keep the app easy to self-host and easy to understand.
- **Use `t()` helper in views for all user-facing text. Never hardcode English strings. Add translations to both `en.yml` and `de.yml`.**
