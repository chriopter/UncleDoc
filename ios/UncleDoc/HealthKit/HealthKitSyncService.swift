import HealthKit

class HealthKitSyncService {
    private let healthKitManager = HealthKitManager.shared
    private let apiClient = APIClient.shared

    // TODO: Implement sync flow:
    // 1. Query new HKCategorySamples for sleepAnalysis since last anchor
    // 2. Filter to actual sleep values (.asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified)
    // 3. Map each sample to HealthKitEntryPayload
    // 4. POST to /api/v1/people/:id/healthkit_entries
    // 5. Update stored anchor on success
}
