import Foundation
import HealthKit

private enum HealthKitCoverage {
    // Stable normal-app HealthKit coverage. Keep this list explicit and reviewable.

    static let characteristicIdentifiers: [HKCharacteristicTypeIdentifier] = [
        .activityMoveMode,
        .biologicalSex,
        .bloodType,
        .dateOfBirth,
        .fitzpatrickSkinType,
        .wheelchairUse
    ]

    static let quantityGroups: [(name: String, identifiers: [HKQuantityTypeIdentifier])] = [
        (
            name: "Activity and Fitness",
            identifiers: [
                .activeEnergyBurned,
                .basalEnergyBurned,
                .distanceCycling,
                .distanceWalkingRunning,
                .flightsClimbed,
                .nikeFuel,
                .stepCount,
                .vo2Max,
                .walkingHeartRateAverage,
                .walkingSpeed,
                .walkingStepLength
            ]
        ),
        (
            name: "Heart and Cardiovascular",
            identifiers: [
                .bloodPressureDiastolic,
                .bloodPressureSystolic,
                .heartRate,
                .heartRateVariabilitySDNN,
                .oxygenSaturation,
                .peripheralPerfusionIndex,
                .restingHeartRate,
                .respiratoryRate
            ]
        ),
        (
            name: "Body Measurements",
            identifiers: [
                .bodyFatPercentage,
                .bodyMass,
                .bodyMassIndex,
                .bodyTemperature,
                .height,
                .leanBodyMass
            ]
        ),
        (
            name: "Respiratory and Labs",
            identifiers: [
                .bloodGlucose,
                .forcedExpiratoryVolume1,
                .forcedVitalCapacity,
                .peakExpiratoryFlowRate
            ]
        ),
        (
            name: "Nutrition",
            identifiers: [
                .dietaryCarbohydrates,
                .dietaryEnergyConsumed,
                .dietaryFatTotal,
                .dietaryProtein,
                .dietarySugar,
                .dietaryWater
            ]
        )
    ]

    static let categoryGroups: [(name: String, identifiers: [HKCategoryTypeIdentifier])] = [
        (
            name: "Activity and Environment",
            identifiers: [
                .appleWalkingSteadinessEvent,
                .appleStandHour,
                .highHeartRateEvent,
                .irregularHeartRhythmEvent,
                .lowCardioFitnessEvent,
                .lowHeartRateEvent,
                .toothbrushingEvent
            ]
        ),
        (
            name: "Sleep and Mindfulness",
            identifiers: [
                .environmentalAudioExposureEvent,
                .mindfulSession,
                .sleepAnalysis
            ]
        ),
        (
            name: "Reproductive Health",
            identifiers: [
                .intermenstrualBleeding
            ]
        )
    ]

    static let specialSampleTypes: [HKSampleType] = [
        HKObjectType.workoutType(),
        HKObjectType.audiogramSampleType(),
        HKObjectType.electrocardiogramType(),
        HKObjectType.stateOfMindType()
    ]

    static let seriesTypes: [HKSeriesType] = [
        HKSeriesType.workoutRoute(),
        HKSeriesType.heartbeat()
    ]
}

struct HealthRecordPreview: Identifiable, Sendable {
    let id: UUID
    let title: String
    let rawText: String
    let startDate: Date
    let endDate: Date?

    init(id: UUID = UUID(), title: String, rawText: String, startDate: Date, endDate: Date? = nil) {
        self.id = id
        self.title = title
        self.rawText = rawText
        self.startDate = startDate
        self.endDate = endDate
    }
}

final class HealthKitManager: @unchecked Sendable {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    private lazy var characteristicTypes: [HKCharacteristicType] = HealthKitCoverage.characteristicIdentifiers.compactMap(HKCharacteristicType.init)
    private lazy var seriesTypes: [HKSeriesType] = HealthKitCoverage.seriesTypes

    private lazy var sampleTypes: [HKSampleType] = {
        var types: [HKSampleType] = []

        HealthKitCoverage.quantityGroups.flatMap(\.identifiers).forEach { identifier in
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.append(type)
            }
        }

        HealthKitCoverage.categoryGroups.flatMap(\.identifiers).forEach { identifier in
            if let type = HKObjectType.categoryType(forIdentifier: identifier) {
                types.append(type)
            }
        }

        types.append(contentsOf: HealthKitCoverage.specialSampleTypes)
        types.append(contentsOf: seriesTypes)

        return Array(Set(types)).sorted { $0.identifier < $1.identifier }
    }()

    private lazy var readTypes: Set<HKObjectType> = {
        Set(sampleTypes)
            .union(characteristicTypes)
            .filter { !$0.requiresPerObjectAuthorization() }
    }()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func loadRecentRecords(limit: Int = 20, maxPerType: Int = 2) async throws -> [HealthRecordPreview] {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        let perTypeLimit = max(maxPerType, 1)
        let collected = await withTaskGroup(of: [HealthRecordPreview].self) { group in
            for sampleType in sampleTypes {
                group.addTask { [healthStore] in
                    do {
                        if sampleType is HKSeriesType {
                            return []
                        }

                        return try await Self.fetchRecords(for: sampleType, healthStore: healthStore, limit: perTypeLimit)
                    } catch {
                        return []
                    }
                }
            }

            group.addTask { [healthStore] in
                Self.fetchCharacteristicRecords(healthStore: healthStore)
            }

            var rows: [HealthRecordPreview] = []
            for await result in group {
                rows.append(contentsOf: result)
            }

            return rows
        }

        return collected
            .sorted { $0.startDate > $1.startDate }
            .prefix(limit)
            .map { $0 }
    }

    private static func fetchRecords(for sampleType: HKSampleType, healthStore: HKHealthStore, limit: Int) async throws -> [HealthRecordPreview] {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let queryLimit = max(limit * 2, limit)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let query = HKSampleQuery(sampleType: sampleType, predicate: nil, limit: queryLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }

            healthStore.execute(query)
        }

        return samples.prefix(limit).map { sample in
            makePreview(from: sample)
        }
    }

    private static func fetchCharacteristicRecords(healthStore: HKHealthStore) -> [HealthRecordPreview] {
        var records: [HealthRecordPreview] = []
        let now = Date()

        func append(_ title: String, value: String?) {
            guard let value else { return }
            records.append(HealthRecordPreview(title: title, rawText: value, startDate: now, endDate: nil))
        }

        do {
            let value = try healthStore.dateOfBirthComponents()
            append("characteristic.dateOfBirth", value: String(describing: value))
        } catch {}

        do {
            let value = try healthStore.biologicalSex()
            append("characteristic.biologicalSex", value: String(describing: value))
        } catch {}

        do {
            let value = try healthStore.bloodType()
            append("characteristic.bloodType", value: String(describing: value))
        } catch {}

        do {
            let value = try healthStore.fitzpatrickSkinType()
            append("characteristic.fitzpatrickSkinType", value: String(describing: value))
        } catch {}

        do {
            let value = try healthStore.wheelchairUse()
            append("characteristic.wheelchairUse", value: String(describing: value))
        } catch {}

        do {
            let value = try healthStore.activityMoveMode()
            append("characteristic.activityMoveMode", value: String(describing: value))
        } catch {}

        return records
    }

    private static func makePreview(from sample: HKSample) -> HealthRecordPreview {
        HealthRecordPreview(
            title: sample.sampleType.identifier,
            rawText: rawDump(for: sample),
            startDate: sample.startDate,
            endDate: sample.endDate
        )
    }

    private static func rawDump(for sample: HKSample) -> String {
        var sections: [[String]] = [
            baseLines(for: sample)
        ]

        if let quantitySample = sample as? HKQuantitySample {
            sections.append([
                "quantityType: quantity",
                "quantity: \(quantitySample.quantity)"
            ])
        }

        if let categorySample = sample as? HKCategorySample {
            sections.append([
                "sampleKind: category",
                "value: \(categorySample.value)"
            ])
        }

        if let workout = sample as? HKWorkout {
            sections.append([
                "sampleKind: workout",
                "activityType: \(workout.workoutActivityType.rawValue)",
                "duration: \(workout.duration)",
                "totalDistance: \(String(describing: workout.totalDistance))",
                "workoutEvents.count: \(workout.workoutEvents?.count ?? 0)"
            ])
        }

        if let audiogram = sample as? HKAudiogramSample {
            sections.append([
                "sampleKind: audiogram",
                "sensitivityPoints.count: \(audiogram.sensitivityPoints.count)",
                "sensitivityPoints: \(clipped(String(describing: audiogram.sensitivityPoints), field: "sensitivityPoints"))"
            ])
        }

        if let electrocardiogram = sample as? HKElectrocardiogram {
            sections.append([
                "sampleKind: electrocardiogram",
                "numberOfVoltageMeasurements: \(electrocardiogram.numberOfVoltageMeasurements)",
                "samplingFrequency: \(String(describing: electrocardiogram.samplingFrequency))",
                "classification: \(electrocardiogram.classification.rawValue)",
                "averageHeartRate: \(String(describing: electrocardiogram.averageHeartRate))",
                "symptomsStatus: \(electrocardiogram.symptomsStatus.rawValue)"
            ])
        }

        if let stateOfMind = sample as? HKStateOfMind {
            sections.append([
                "sampleKind: stateOfMind",
                clipped(String(describing: stateOfMind), field: "stateOfMind")
            ])
        }

        if let heartbeatSeries = sample as? HKHeartbeatSeriesSample {
            sections.append([
                "sampleKind: heartbeatSeries",
                "heartbeatSeries.count: \(heartbeatSeries.count)"
            ])
        }

        if let workoutRoute = sample as? HKWorkoutRoute {
            sections.append([
                "sampleKind: workoutRoute",
                clipped(String(describing: workoutRoute), field: "workoutRoute")
            ])
        }

        if let metadata = sample.metadata, !metadata.isEmpty {
            sections.append([
                "metadata: \(clipped(String(describing: metadata), field: "metadata"))"
            ])
        }

        sections.append([
            "debug: \(clipped(String(describing: sample), field: "debug"))"
        ])

        return clipped(
            sections
                .map { $0.joined(separator: "\n") }
                .joined(separator: "\n\n"),
            field: "sample"
        )
    }

    private static func baseLines(for sample: HKSample) -> [String] {
        [
            "type: \(sample.sampleType.identifier)",
            "uuid: \(sample.uuid.uuidString)",
            "startDate: \(sample.startDate.ISO8601Format())",
            "endDate: \(sample.endDate.ISO8601Format())",
            "device: \(String(describing: sample.device))",
            "source: \(sample.sourceRevision.source.name)",
            "source.bundleIdentifier: \(sample.sourceRevision.source.bundleIdentifier)",
            "source.version: \(sample.sourceRevision.version ?? "-")",
            "productType: \(sample.sourceRevision.productType ?? "-")"
        ]
    }

    private static func clipped(_ value: String, field: String, limit: Int = 4000) -> String {
        guard value.count > limit else {
            return value
        }

        let prefix = value.prefix(limit)
        return "\(prefix)\n... [truncated \(field), total chars: \(value.count)]"
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
