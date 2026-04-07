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

## iOS App

- This repo also includes a native iOS app in `ios/UncleDoc.xcodeproj`.
- The iOS app is a thin Hotwire Native shell around the Rails app, so prefer keeping product UI and flow in Rails unless the feature is truly device-specific.
- Native app requests identify themselves with the `UncleDoc iOS` user agent; use `native_app_request?` when the web UI needs iOS-specific adjustments.
- When changing shared layouts, preserve native app behavior too: respect safe areas, avoid horizontal overflow, and avoid browser-style zoom or sideways drift inside the app shell.
- Put native-only work in Swift for device capabilities like HealthKit, server onboarding, and other OS integrations.

## Local Deployment

- This app is currently run on a LAN-only server from `/root/uncledoc`.
- The app is managed by `systemd` via `uncledoc-dev.service`.
- The service runs `bin/dev`, keeps Rails in `development`, and binds to `0.0.0.0:3000`.
- Persistent app data for this setup lives in `storage/development.sqlite3`.
- In practice, this dev environment is used like a production environment because it contains live persistent data.
- Agents must treat local data as valuable: avoid destructive actions, do not casually delete records or files, and require explicit user intent before removing data.
- If operational docs change, keep `README.md` aligned with the live service setup.

## User Preferences

- User preferences (locale, date format) are stored in the `user_preferences` table.
- Access via `UserPreference.current` - returns the singleton preference record.
- Update via `UserPreference.update_locale(locale)` and `UserPreference.update_date_format(format)`.
- Locale and date format can be set via URL params: `?locale=de&date_format=long`
- Preferences are automatically saved when visiting `/settings/profile?locale=de&date_format=long`
- The application automatically sets `I18n.locale` from user preferences on each request.
