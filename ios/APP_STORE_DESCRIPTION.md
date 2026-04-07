# UncleDoc iOS App Description

UncleDoc is a self-hosted family health manager for iPhone and your home server. It keeps health information for everyone in your household in one private place.

## What You Can Do

- Track multiple people in one household
- Log health notes, facts, measurements, and documents in a timeline
- View trends for weight, vitals, and other recurring measurements
- Sync HealthKit data from your iPhone directly into your UncleDoc server
- Use Baby mode for quick logging of feeding, diapers, sleep, and growth
- Browse each person's Overview, Log, Trends, Calendar, and Files

## HealthKit Sync

The app reads health data from Apple Health and syncs it into your personal UncleDoc server. Measurements collected on your iPhone, such as steps, heart rate, and weight, can appear alongside your manual notes and uploaded documents. HealthKit data is synced to infrastructure you control.

## Privacy First

UncleDoc is self-hosted. There is no central UncleDoc cloud, no required UncleDoc account, and no subscription fee.

If you enable AI features, you choose the LLM provider yourself. Any data sent to an LLM depends on the provider and configuration you decide to use.

## Optional AI Features

If you connect an LLM provider, UncleDoc can parse free-text notes into structured records, generate summaries, and answer questions about a person's history. The app works fully without this feature.

UncleDoc is a record-keeping tool, not a medical device, and does not provide medical advice, diagnosis, or treatment.

## Languages

Supports English and German.

Note: UncleDoc requires a running instance of the UncleDoc Rails server on your local network or home server. See the project README for setup instructions.
