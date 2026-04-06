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

    // This is the stable database sync subset. Keep it intentionally narrow so first sync
    // is practical, resumable, and useful for analysis instead of importing millions of rows.
    static let syncQuantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .bloodGlucose,
        .bloodPressureDiastolic,
        .bloodPressureSystolic,
        .bodyFatPercentage,
        .bodyMass,
        .bodyMassIndex,
        .bodyTemperature,
        .height,
        .restingHeartRate,
        .walkingHeartRateAverage
    ]

    static let syncCategoryIdentifiers: [HKCategoryTypeIdentifier] = [
        .highHeartRateEvent,
        .irregularHeartRhythmEvent,
        .lowHeartRateEvent,
        .mindfulSession
    ]

    static let syncSpecialSampleTypeIdentifiers: [String] = [
        HKObjectType.electrocardiogramType().identifier,
        HKObjectType.stateOfMindType().identifier
    ]

    static let dailyAggregateQuantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .stepCount,
        .activeEnergyBurned,
        .basalEnergyBurned,
        .heartRate,
        .heartRateVariabilitySDNN,
        .oxygenSaturation,
        .respiratoryRate
    ]

    static let dailyAggregateCategoryIdentifiers: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis
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

struct HealthKitSyncBatch: Sendable {
    let records: [HealthKitRecordPayload]
    let anchorData: Data?
    let hasMore: Bool
}

enum HealthRecordXMLExporter {
    static func exportXML(records: [HealthRecordPreview], limit: Int = 100) -> String {
        let formatter = ISO8601DateFormatter()
        let body = records.prefix(limit).map { record in
            """
              <record>
                <title>\(escape(record.title))</title>
                <startDate>\(formatter.string(from: record.startDate))</startDate>
                <endDate>\(record.endDate.map(formatter.string(from:)) ?? "")</endDate>
                <rawText>\(escape(record.rawText))</rawText>
              </record>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <healthRecords exportedAt="\(formatter.string(from: Date()))" count="\(min(records.count, limit))">
        \(body)
        </healthRecords>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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

    private let analysisPriorityTypeIdentifiers: [String] = [
        HKQuantityTypeIdentifier.bodyMass.rawValue,
        HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
        HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue,
        HKQuantityTypeIdentifier.heartRate.rawValue
    ]

    var syncableSampleTypes: [HKSampleType] {
        sampleTypes.filter { sampleType in
            if let quantityType = sampleType as? HKQuantityType {
                return HealthKitCoverage.syncQuantityIdentifiers.contains(where: { $0.rawValue == quantityType.identifier })
            }

            if let categoryType = sampleType as? HKCategoryType {
                return HealthKitCoverage.syncCategoryIdentifiers.contains(where: { $0.rawValue == categoryType.identifier })
            }

            return HealthKitCoverage.syncSpecialSampleTypeIdentifiers.contains(sampleType.identifier)
        }
    }

    var dailyAggregateSampleTypes: [HKQuantityType] {
        HealthKitCoverage.dailyAggregateQuantityIdentifiers.compactMap(HKObjectType.quantityType(forIdentifier:))
    }

    var dailyAggregateCategoryTypes: [HKCategoryType] {
        HealthKitCoverage.dailyAggregateCategoryIdentifiers.compactMap(HKObjectType.categoryType(forIdentifier:))
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func estimateInitialRecordCount() async throws -> Int {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        let counts = await withTaskGroup(of: Int.self) { group in
            for sampleType in syncableSampleTypes {
                group.addTask { [healthStore] in
                    do {
                        if sampleType is HKSeriesType {
                            return 0
                        }

                        return try await Self.countRecords(for: sampleType, healthStore: healthStore)
                    } catch {
                        return 0
                    }
                }
            }

            var total = 0
            for await count in group {
                total += count
            }
            return total
        }

        return counts + HealthKitCoverage.characteristicIdentifiers.count
    }

    func estimateDailyAggregateCount() async throws -> Int {
        let calendar = Calendar.current
        let now = Date()
        var total = 0

        for sampleType in dailyAggregateSampleTypes {
            if let startDate = try await Self.earliestStartDate(for: sampleType, healthStore: healthStore) {
                let startDay = calendar.startOfDay(for: startDate)
                let today = calendar.startOfDay(for: now)
                let days = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
                total += max(days + 1, 1)
            }
        }

        for sampleType in dailyAggregateCategoryTypes {
            if let startDate = try await Self.earliestStartDate(for: sampleType, healthStore: healthStore) {
                let startDay = calendar.startOfDay(for: startDate)
                let today = calendar.startOfDay(for: now)
                let days = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
                total += max(days + 1, 1)
            }
        }

        return total
    }

    func estimateSyncTypeCounts() async throws -> [(String, Int)] {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        var results: [(String, Int)] = []

        results.append(contentsOf: HealthKitCoverage.characteristicIdentifiers.map { ("characteristic.\($0.rawValue)", 1) })

        let rawCounts = await withTaskGroup(of: (String, Int).self) { group in
            for sampleType in syncableSampleTypes {
                group.addTask { [healthStore] in
                    do {
                        let count = try await Self.countRecords(for: sampleType, healthStore: healthStore)
                        return (sampleType.identifier, count)
                    } catch {
                        return (sampleType.identifier, 0)
                    }
                }
            }

            var values: [(String, Int)] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        results.append(contentsOf: rawCounts)

        let calendar = Calendar.current
        let now = Date()
        for sampleType in dailyAggregateSampleTypes {
            let count: Int
            if let startDate = try await Self.earliestStartDate(for: sampleType, healthStore: healthStore) {
                let startDay = calendar.startOfDay(for: startDate)
                let today = calendar.startOfDay(for: now)
                count = max((calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1, 1)
            } else {
                count = 0
            }
            results.append(("daily.\(sampleType.identifier)", count))
        }

        for sampleType in dailyAggregateCategoryTypes {
            let count: Int
            if let startDate = try await Self.earliestStartDate(for: sampleType, healthStore: healthStore) {
                let startDay = calendar.startOfDay(for: startDate)
                let today = calendar.startOfDay(for: now)
                count = max((calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1, 1)
            } else {
                count = 0
            }
            results.append(("daily.\(sampleType.identifier)", count))
        }

        return results.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
            return lhs.1 > rhs.1
        }
    }

    func characteristicSyncRecords(deviceID: String) -> [HealthKitRecordPayload] {
        let baseDate = Date(timeIntervalSince1970: 0).ISO8601Format()

        return Self.fetchCharacteristicRecords(healthStore: healthStore).map { record in
            HealthKitRecordPayload(
                externalID: "\(deviceID)-\(record.title)",
                recordType: record.title,
                sourceName: "HealthKit Characteristic",
                startAt: baseDate,
                endAt: nil,
                payload: [
                    "title": record.title,
                    "raw_text": record.rawText,
                    "device_id": deviceID,
                    "kind": "characteristic"
                ]
            )
        }
    }

    func fetchAnchoredBatch(for sampleType: HKSampleType, anchorData: Data?, limit: Int) async throws -> HealthKitSyncBatch {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        let anchor = anchorData.flatMap(Self.decodeAnchor)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: sampleType, predicate: nil, anchor: anchor, limit: limit, resultsHandler: { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let records = (samples ?? []).compactMap(Self.makeSyncPayload(from:))
                let encodedAnchor = newAnchor.flatMap(Self.encodeAnchor)
                continuation.resume(returning: HealthKitSyncBatch(records: records, anchorData: encodedAnchor, hasMore: (samples ?? []).count >= limit))
            })

            healthStore.execute(query)
        }
    }

    func fetchDailyAggregateRecords(from startDate: Date, to endDate: Date) async throws -> [HealthKitRecordPayload] {
        let chunks = try await withThrowingTaskGroup(of: [HealthKitRecordPayload].self) { group in
            for sampleType in dailyAggregateSampleTypes {
                group.addTask { [healthStore] in
                    try await Self.fetchDailyAggregates(for: sampleType, healthStore: healthStore, from: startDate, to: endDate)
                }
            }

            for sampleType in dailyAggregateCategoryTypes {
                group.addTask { [healthStore] in
                    try await Self.fetchDailyCategoryAggregates(for: sampleType, healthStore: healthStore, from: startDate, to: endDate)
                }
            }

            var rows: [HealthKitRecordPayload] = []
            for try await chunk in group {
                rows.append(contentsOf: chunk)
            }
            return rows
        }

        return chunks.sorted { $0.startAt > $1.startAt }
    }

    func loadRecentRecords(limit: Int = 20, maxPerType: Int = 2) async throws -> [HealthRecordPreview] {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        let perTypeLimit = max(maxPerType, 1)
        let collected = await withTaskGroup(of: [HealthRecordPreview].self) { group in
            for sampleType in syncableSampleTypes {
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

    func loadExportRecords(totalLimit: Int = 100, since startDate: Date) async throws -> [HealthRecordPreview] {
        guard isAvailable else {
            throw HealthKitManagerError.notAvailable
        }

        let endDate = Date()

        let collected = await withTaskGroup(of: [HealthRecordPreview].self) { group in
            for sampleType in sampleTypes {
                group.addTask { [healthStore] in
                    do {
                        if sampleType is HKSeriesType {
                            return []
                        }

                        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

                        return try await Self.fetchRecords(
                            for: sampleType,
                            healthStore: healthStore,
                            predicate: predicate,
                            limit: totalLimit
                        )
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

        return prioritize(records: collected, totalLimit: totalLimit)
    }

    private static func fetchRecords(
        for sampleType: HKSampleType,
        healthStore: HKHealthStore,
        predicate: NSPredicate? = nil,
        limit: Int
    ) async throws -> [HealthRecordPreview] {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let queryLimit = max(limit * 2, limit)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: queryLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
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
        let stableDate = Date(timeIntervalSince1970: 0)

        func append(_ title: String, value: String?) {
            guard let value else { return }
            records.append(HealthRecordPreview(title: title, rawText: value, startDate: stableDate, endDate: nil))
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

    private func prioritize(records: [HealthRecordPreview], totalLimit: Int) -> [HealthRecordPreview] {
        let sorted = records.sorted { $0.startDate > $1.startDate }
        let grouped = Dictionary(grouping: sorted, by: \.title)

        var selected: [HealthRecordPreview] = []
        var seen = Set<UUID>()

        for identifier in analysisPriorityTypeIdentifiers {
            for record in grouped[identifier, default: []] {
                if seen.insert(record.id).inserted {
                    selected.append(record)
                }
            }
        }

        for record in sorted where selected.count < totalLimit {
            if seen.insert(record.id).inserted {
                selected.append(record)
            }
        }

        return Array(selected.prefix(totalLimit))
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

    private static func countRecords(for sampleType: HKSampleType, healthStore: HKHealthStore) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: nil, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.count ?? 0)
                }
            }

            healthStore.execute(query)
        }
    }

    private static func earliestStartDate(for sampleType: HKSampleType, healthStore: HKHealthStore) async throws -> Date? {
        try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: sampleType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first?.startDate)
                }
            }

            healthStore.execute(query)
        }
    }

    private static func fetchDailyAggregates(for sampleType: HKQuantityType, healthStore: HKHealthStore, from startDate: Date, to endDate: Date) async throws -> [HealthKitRecordPayload] {
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: startDate)
        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let options = statisticsOptions(for: sampleType)

        let unit = preferredUnit(for: sampleType)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: sampleType, quantitySamplePredicate: predicate, options: options, anchorDate: anchorDate, intervalComponents: interval)
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var rows: [HealthKitRecordPayload] = []
                collection.enumerateStatistics(from: anchorDate, to: endDate) { statistics, _ in
                    let dayStart = calendar.startOfDay(for: statistics.startDate)
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? statistics.endDate
                    let fields = statisticsPayloadFields(for: statistics, sampleType: sampleType, unit: unit)
                    guard !fields.isEmpty else { return }

                    rows.append(
                        HealthKitRecordPayload(
                            externalID: "daily:\(sampleType.identifier):\(dayStart.ISO8601Format())",
                            recordType: "daily.\(sampleType.identifier)",
                            sourceName: "HealthKit Daily Aggregate",
                            startAt: dayStart.ISO8601Format(),
                            endAt: dayEnd.ISO8601Format(),
                            payload: [
                                "kind": "daily_aggregate",
                                "sample_type": sampleType.identifier,
                                "unit": unit.unitString,
                                "start_date": dayStart.ISO8601Format(),
                                "end_date": dayEnd.ISO8601Format()
                            ].merging(fields) { _, new in new }
                        )
                    )
                }

                continuation.resume(returning: rows)
            }

            healthStore.execute(query)
        }
    }

    private static func preferredUnit(for sampleType: HKQuantityType) -> HKUnit {
        switch sampleType.identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return .count()
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue:
            return .kilocalorie()
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return .secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return .percent()
        default:
            return .count()
        }
    }

    private static func statisticsOptions(for sampleType: HKQuantityType) -> HKStatisticsOptions {
        switch sampleType.identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue:
            return .cumulativeSum
        default:
            return [ .discreteAverage, .discreteMin, .discreteMax ]
        }
    }

    private static func statisticsPayloadFields(for statistics: HKStatistics, sampleType: HKQuantityType, unit: HKUnit) -> [String: String] {
        if [
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.basalEnergyBurned.rawValue
        ].contains(sampleType.identifier), let sum = statistics.sumQuantity() {
            return [ "sum": String(describing: sum.doubleValue(for: unit)) ]
        }

        var fields: [String: String] = [:]
        if let average = statistics.averageQuantity() {
            fields["average"] = String(describing: average.doubleValue(for: unit))
        }
        if let minimum = statistics.minimumQuantity() {
            fields["min"] = String(describing: minimum.doubleValue(for: unit))
        }
        if let maximum = statistics.maximumQuantity() {
            fields["max"] = String(describing: maximum.doubleValue(for: unit))
        }
        return fields
    }

    private static func fetchDailyCategoryAggregates(for sampleType: HKCategoryType, healthStore: HKHealthStore, from startDate: Date, to endDate: Date) async throws -> [HealthKitRecordPayload] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
            }

            healthStore.execute(query)
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples, by: { calendar.startOfDay(for: $0.startDate) })

        return grouped.keys.sorted().compactMap { dayStart in
            guard let daySamples = grouped[dayStart], !daySamples.isEmpty else { return nil }

            let totalDuration = daySamples.reduce(0.0) { partial, sample in
                partial + sample.endDate.timeIntervalSince(sample.startDate)
            }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            return HealthKitRecordPayload(
                externalID: "daily:\(sampleType.identifier):\(dayStart.ISO8601Format())",
                recordType: "daily.\(sampleType.identifier)",
                sourceName: "HealthKit Daily Aggregate",
                startAt: dayStart.ISO8601Format(),
                endAt: dayEnd.ISO8601Format(),
                payload: [
                    "kind": "daily_category_aggregate",
                    "sample_type": sampleType.identifier,
                    "count": String(daySamples.count),
                    "duration_seconds": String(Int(totalDuration.rounded())),
                    "start_date": dayStart.ISO8601Format(),
                    "end_date": dayEnd.ISO8601Format()
                ]
            )
        }
    }

    private static func makeSyncPayload(from sample: HKSample) -> HealthKitRecordPayload? {
        let sourceName = sample.sourceRevision.source.name
        let payload = syncPayloadFields(for: sample)

        return HealthKitRecordPayload(
            externalID: sample.uuid.uuidString,
            recordType: sample.sampleType.identifier,
            sourceName: sourceName,
            startAt: sample.startDate.ISO8601Format(),
            endAt: sample.endDate.ISO8601Format(),
            payload: payload
        )
    }

    private static func syncPayloadFields(for sample: HKSample) -> [String: String] {
        var payload: [String: String] = [
            "type": sample.sampleType.identifier,
            "uuid": sample.uuid.uuidString,
            "start_date": sample.startDate.ISO8601Format(),
            "end_date": sample.endDate.ISO8601Format(),
            "device": String(describing: sample.device),
            "source_name": sample.sourceRevision.source.name,
            "source_bundle_identifier": sample.sourceRevision.source.bundleIdentifier,
            "source_version": sample.sourceRevision.version ?? "",
            "product_type": sample.sourceRevision.productType ?? "",
            "raw_text": rawDump(for: sample)
        ]

        if let quantitySample = sample as? HKQuantitySample {
            payload["quantity"] = String(describing: quantitySample.quantity)
        }

        if let categorySample = sample as? HKCategorySample {
            payload["value"] = String(categorySample.value)
        }

        if let metadata = sample.metadata, !metadata.isEmpty {
            payload["metadata"] = clipped(String(describing: metadata), field: "metadata")
        }

        return payload
    }

    private static func encodeAnchor(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    private static func decodeAnchor(_ data: Data) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
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
