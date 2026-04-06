import HealthKit

class HealthKitManager {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    // TODO: Implement anchored queries for incremental sync
    // TODO: Enable background delivery with .hourly frequency
    // TODO: Query sleep analysis samples and map to Entry format
}
