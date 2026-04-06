import Foundation
import HealthKit

private enum HealthKitCoverage {
    // Review and extend these lists here when adding more public HealthKit coverage.

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
                .dietaryEnergyConsumed,
                .dietaryWater
            ]
        )
    ]

    static let categoryGroups: [(name: String, identifiers: [HKCategoryTypeIdentifier])] = [
        (
            name: "Activity and Environment",
            identifiers: [
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

    static let correlationIdentifiers: [HKCorrelationTypeIdentifier] = [
        .bloodPressure,
        .food
    ]

    static let specialSampleTypes: [HKSampleType] = [
        HKObjectType.workoutType(),
        HKObjectType.audiogramSampleType(),
        HKObjectType.electrocardiogramType(),
        HKSeriesType.workoutRoute(),
        HKSeriesType.heartbeat(),
        HKObjectType.visionPrescriptionType(),
        HKObjectType.stateOfMindType(),
        HKObjectType.medicationDoseEventType()
    ]

    static let documentTypes: [HKDocumentType] = [
        .init(.CDA)
    ].compactMap { $0 }
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

    private lazy var correlationTypes: [HKCorrelationType] = HealthKitCoverage.correlationIdentifiers.compactMap(HKCorrelationType.init)

    private lazy var documentTypes: [HKDocumentType] = HealthKitCoverage.documentTypes

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

        types.append(contentsOf: correlationTypes)
        types.append(contentsOf: HealthKitCoverage.specialSampleTypes)
        types.append(contentsOf: documentTypes)

        return Array(Set(types)).sorted { $0.identifier < $1.identifier }
    }()

    private lazy var readTypes: Set<HKObjectType> = Set(sampleTypes).union(characteristicTypes)

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
            for sampleType in sampleTypes {
                group.addTask { [healthStore] in
                    if let documentType = sampleType as? HKDocumentType {
                        return try await Self.fetchDocumentRecords(for: documentType, healthStore: healthStore, limit: perTypeLimit)
                    }

                    return try await Self.fetchRecords(for: sampleType, healthStore: healthStore, limit: perTypeLimit)
                }
            }

            group.addTask { [healthStore] in
                Self.fetchCharacteristicRecords(healthStore: healthStore)
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

    private static func fetchDocumentRecords(for documentType: HKDocumentType, healthStore: HKHealthStore, limit: Int) async throws -> [HealthRecordPreview] {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKDocumentSample], Error>) in
            let query = HKDocumentQuery(
                documentType: documentType,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sortDescriptor],
                includeDocumentData: true
            ) { _, results, done, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if done {
                    continuation.resume(returning: results ?? [])
                }
            }

            healthStore.execute(query)
        }

        return samples.map { makePreview(from: $0) }
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
        var lines: [String] = [
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

        if let quantitySample = sample as? HKQuantitySample {
            lines.append("quantity: \(quantitySample.quantity)")
        }

        if let categorySample = sample as? HKCategorySample {
            lines.append("value: \(categorySample.value)")
        }

        if let workout = sample as? HKWorkout {
            lines.append("activityType: \(workout.workoutActivityType.rawValue)")
            lines.append("duration: \(workout.duration)")
            if let totalDistance = workout.totalDistance {
                lines.append("totalDistance: \(totalDistance)")
            }
            lines.append("workoutEvents.count: \(workout.workoutEvents?.count ?? 0)")
        }

        if let correlation = sample as? HKCorrelation {
            lines.append("correlationType: \(correlation.correlationType.identifier)")
            lines.append("objects.count: \(correlation.objects.count)")
            lines.append("objects: \(correlation.objects.map { $0.sampleType.identifier })")
        }

        if let cdaDocument = sample as? HKCDADocumentSample {
            lines.append("documentType: \(cdaDocument.documentType.identifier)")
            lines.append("documentTitle: \(cdaDocument.document?.title ?? "-")")
            lines.append("patientName: \(cdaDocument.document?.patientName ?? "-")")
            lines.append("authorName: \(cdaDocument.document?.authorName ?? "-")")
            lines.append("custodianName: \(cdaDocument.document?.custodianName ?? "-")")
            if let documentData = cdaDocument.document?.documentData,
               let xml = String(data: documentData, encoding: .utf8) {
                lines.append("documentData: \(xml)")
            }
        }

        if let audiogram = sample as? HKAudiogramSample {
            lines.append("sensitivityPoints.count: \(audiogram.sensitivityPoints.count)")
            lines.append("sensitivityPoints: \(audiogram.sensitivityPoints)")
        }

        if let electrocardiogram = sample as? HKElectrocardiogram {
            lines.append("numberOfVoltageMeasurements: \(electrocardiogram.numberOfVoltageMeasurements)")
            lines.append("samplingFrequency: \(String(describing: electrocardiogram.samplingFrequency))")
            lines.append("classification: \(electrocardiogram.classification.rawValue)")
            lines.append("averageHeartRate: \(String(describing: electrocardiogram.averageHeartRate))")
            lines.append("symptomsStatus: \(electrocardiogram.symptomsStatus.rawValue)")
        }

        if let visionPrescription = sample as? HKVisionPrescription {
            lines.append("visionPrescription: \(String(describing: visionPrescription))")
        }

        if let stateOfMind = sample as? HKStateOfMind {
            lines.append("stateOfMind: \(String(describing: stateOfMind))")
        }

        if let medicationDoseEvent = sample as? HKMedicationDoseEvent {
            lines.append("medicationDoseEvent: \(String(describing: medicationDoseEvent))")
        }

        if let heartbeatSeries = sample as? HKHeartbeatSeriesSample {
            lines.append("heartbeatSeries.count: \(heartbeatSeries.count)")
        }

        if let workoutRoute = sample as? HKWorkoutRoute {
            lines.append("workoutRoute: \(String(describing: workoutRoute))")
        }

        if let metadata = sample.metadata, !metadata.isEmpty {
            lines.append("metadata: \(metadata)")
        }

        lines.append("debug: \(String(describing: sample))")
        return lines.joined(separator: "\n")
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
