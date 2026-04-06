# iOS App Plan

## One-time Mac setup

1. Open `ios/UncleDoc.xcodeproj` in Xcode
2. Set team/signing identity (Target → Signing & Capabilities)
3. Add `turbo-ios` SPM package (File → Add Package Dependencies → `https://github.com/hotwired/turbo-ios`)
4. Configure Xcode Cloud (Product → Xcode Cloud → Create Workflow)
   - Connect to GitHub repo
   - Set custom build root to `ios/`
   - Trigger: push to `main` with `ios/` changes → TestFlight
   - Trigger: tag `ios-v*` → App Store submission
   - Enable automatic code signing
5. Build & run once to verify it compiles
6. Push changes (Xcode will update `project.pbxproj` with SPM + signing)

## After Mac setup (all from Linux)

### Rails side
- [ ] Migration: add `source` and `healthkit_uuid` columns to entries
- [ ] API token auth (`app/controllers/api/base_controller.rb`)
- [ ] `POST /api/v1/people/:id/healthkit_entries` — bulk create from HealthKit
- [ ] `GET /api/v1/people/:id/healthkit_entries/last_sync`
- [ ] `GET /api/v1/people` — list people
- [ ] `GET /api/v1/turbo/ios/path_configuration.json` — Turbo Native nav config
- [ ] Turbo Native user-agent detection in `ApplicationController`
- [ ] Hide web nav when inside iOS app

### iOS side (edit Swift files from Linux, Xcode Cloud builds)
- [ ] Replace `ContentView` with Turbo Native navigator + tab bar
- [ ] Implement `HealthKitManager` — authorization + anchored queries
- [ ] Implement `HealthKitSyncService` — map sleep samples → API payloads
- [ ] Implement `APIClient` — bearer token auth, bulk POST entries
- [ ] Background delivery (`.hourly`) for sleep data
- [ ] Native settings screen for person selection + HealthKit toggle

## HealthKit data mapping

| HealthKit Type | Entry type | Notes |
|---|---|---|
| Sleep Analysis | `sleep` | Primary — from Apple Watch |
| Body Mass | (future) | Baby weight |
| Body Temperature | (future) | Fever tracking |

No HealthKit types for feeding or diapers — those stay manual via web views.

## Architecture

- **Deduplication**: `healthkit_uuid` unique index on entries prevents re-imports
- **Sync**: Anchored queries (not time-based) for reliable incremental sync
- **Auth**: Static API token in Rails credentials + iOS Keychain
- **Entries**: HealthKit entries created with `source: "healthkit"`, `parse_status: "parsed"`, no LLM parsing needed
