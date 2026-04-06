import Foundation
import HealthKit

struct HealthRecordPreview: Identifiable, Sendable {
    let id: UUID
    let typeTitle: String
    let summary: String
    let startDate: Date
    let endDate: Date?
    let sourceName: String

    init(id: UUID = UUID(), typeTitle: String, summary: String, startDate: Date, endDate: Date? = nil, sourceName: String) {
        self.id = id
        self.typeTitle = typeTitle
        self.summary = summary
        self.startDate = startDate
        self.endDate = endDate
        self.sourceName = sourceName
    }
}

final class HealthKitManager: @unchecked Sendable {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    private struct RecordType: Sendable {
        let sampleType: HKSampleType
        let title: String
        let preferredUnit: HKUnit?
        let unitLabel: String?
    }

    private lazy var recordTypes: [RecordType] = {
        var types: [RecordType] = []

        func quantity(_ identifier: HKQuantityTypeIdentifier, title: String, unit: HKUnit, unitLabel: String) {
            guard let sampleType = HKObjectType.quantityType(forIdentifier: identifier) else { return }
            types.append(RecordType(sampleType: sampleType, title: title, preferredUnit: unit, unitLabel: unitLabel))
        }

        func category(_ identifier: HKCategoryTypeIdentifier, title: String) {
            guard let sampleType = HKObjectType.categoryType(forIdentifier: identifier) else { return }
            types.append(RecordType(sampleType: sampleType, title: title, preferredUnit: nil, unitLabel: nil))
        }

        if let workoutType = HKObjectType.workoutType() as HKSampleType? {
            types.append(RecordType(sampleType: workoutType, title: "Workout", preferredUnit: nil, unitLabel: nil))
        }

        quantity(.heartRate, title: "Heart Rate", unit: HKUnit.count().unitDivided(by: .minute()), unitLabel: "/min")
        quantity(.stepCount, title: "Step Count", unit: .count(), unitLabel: "count")
        quantity(.activeEnergyBurned, title: "Active Energy Burned", unit: .kilocalorie(), unitLabel: "kcal")
        quantity(.basalEnergyBurned, title: "Basal Energy Burned", unit: .kilocalorie(), unitLabel: "kcal")
        quantity(.bodyMass, title: "Body Mass", unit: .gramUnit(with: .kilo), unitLabel: "kg")
        quantity(.height, title: "Height", unit: .meterUnit(with: .centi), unitLabel: "cm")
        quantity(.bodyMassIndex, title: "BMI", unit: .count(), unitLabel: "")
        quantity(.bodyTemperature, title: "Body Temperature", unit: .degreeCelsius(), unitLabel: "C")
        quantity(.bloodPressureSystolic, title: "Blood Pressure Systolic", unit: .millimeterOfMercury(), unitLabel: "mmHg")
        quantity(.bloodPressureDiastolic, title: "Blood Pressure Diastolic", unit: .millimeterOfMercury(), unitLabel: "mmHg")
        quantity(.oxygenSaturation, title: "Oxygen Saturation", unit: .percent(), unitLabel: "%")
        quantity(.respiratoryRate, title: "Respiratory Rate", unit: HKUnit.count().unitDivided(by: .minute()), unitLabel: "/min")
        quantity(.restingHeartRate, title: "Resting Heart Rate", unit: HKUnit.count().unitDivided(by: .minute()), unitLabel: "/min")
        quantity(.walkingHeartRateAverage, title: "Walking Heart Rate Average", unit: HKUnit.count().unitDivided(by: .minute()), unitLabel: "/min")
        quantity(.distanceWalkingRunning, title: "Walking + Running Distance", unit: .meterUnit(with: .kilo), unitLabel: "km")
        quantity(.flightsClimbed, title: "Flights Climbed", unit: .count(), unitLabel: "count")
        quantity(.bloodGlucose, title: "Blood Glucose", unit: HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)), unitLabel: "mg/dL")
        quantity(.dietaryEnergyConsumed, title: "Dietary Energy", unit: .kilocalorie(), unitLabel: "kcal")
        quantity(.dietaryWater, title: "Dietary Water", unit: .literUnit(with: .milli), unitLabel: "mL")

        category(.sleepAnalysis, title: "Sleep Analysis")
        category(.mindfulSession, title: "Mindful Session")
        category(.intermenstrualBleeding, title: "Intermenstrual Bleeding")
        category(.lowHeartRateEvent, title: "Low Heart Rate Event")
        category(.highHeartRateEvent, title: "High Heart Rate Event")
        category(.irregularHeartRhythmEvent, title: "Irregular Heart Rhythm Event")
        category(.toothbrushingEvent, title: "Toothbrushing Event")

        return types
    }()

    private lazy var readTypes: Set<HKObjectType> = Set(recordTypes.map(\.sampleType))

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func loadRecentRecords(limit: Int = 20, maxPerType: Int = 3) async throws -> [HealthRecordPreview] {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        let perTypeLimit = max(maxPerType, 1)
        let collected = try await withThrowingTaskGroup(of: [HealthRecordPreview].self) { group in
            for recordType in recordTypes {
                group.addTask { [healthStore] in
                    try await Self.fetchRecords(for: recordType, healthStore: healthStore, limit: perTypeLimit)
                }
            }

            var rows: [HealthRecordPreview] = []
            for try await result in group {
                rows.append(contentsOf: result)
            }

            return rows
        }

        return collected
            .sorted { $0.startDate > $1.startDate }
            .prefix(limit)
            .map { $0 }
    }

    private static func fetchRecords(for recordType: RecordType, healthStore: HKHealthStore, limit: Int) async throws -> [HealthRecordPreview] {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let queryLimit = max(limit * 2, limit)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let query = HKSampleQuery(sampleType: recordType.sampleType, predicate: nil, limit: queryLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }

            healthStore.execute(query)
        }

        return samples.prefix(limit).compactMap { sample in
            makePreview(from: sample, recordType: recordType)
        }
    }

    private static func makePreview(from sample: HKSample, recordType: RecordType) -> HealthRecordPreview? {
        let sourceName = sample.sourceRevision.source.name

        if let quantitySample = sample as? HKQuantitySample,
           let unit = recordType.preferredUnit {
            let rawValue = quantitySample.quantity.doubleValue(for: unit)
            return HealthRecordPreview(
                typeTitle: recordType.title,
                summary: formatQuantity(rawValue, unitLabel: recordType.unitLabel),
                startDate: quantitySample.startDate,
                endDate: quantitySample.endDate,
                sourceName: sourceName
            )
        }

        if let categorySample = sample as? HKCategorySample {
            return HealthRecordPreview(
                typeTitle: recordType.title,
                summary: "Value \(categorySample.value)",
                startDate: categorySample.startDate,
                endDate: categorySample.endDate,
                sourceName: sourceName
            )
        }

        if let workout = sample as? HKWorkout {
            let minutes = max(Int(workout.duration / 60), 1)
            return HealthRecordPreview(
                typeTitle: recordType.title,
                summary: "\(minutes) min",
                startDate: workout.startDate,
                endDate: workout.endDate,
                sourceName: sourceName
            )
        }

        return nil
    }

    private static func formatQuantity(_ value: Double, unitLabel: String?) -> String {
        let formattedNumber = value == floor(value) ? String(Int(value)) : String(format: "%.2f", value)
        guard let unitLabel, !unitLabel.isEmpty else {
            return formattedNumber
        }

        return "\(formattedNumber) \(unitLabel)"
    }
}

enum HealthKitManagerError: LocalizedError {
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device."
        }
    }
}
