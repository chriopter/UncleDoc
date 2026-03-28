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

## User Preferences

- User preferences (locale, date format) are stored in the `user_preferences` table.
- Access via `UserPreference.current` - returns the singleton preference record.
- Update via `UserPreference.update_locale(locale)` and `UserPreference.update_date_format(format)`.
- Locale and date format can be set via URL params: `?locale=de&date_format=long`
- Preferences are automatically saved when visiting `/settings/profile?locale=de&date_format=long`
- The application automatically sets `I18n.locale` from user preferences on each request.
