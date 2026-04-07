import BackgroundTasks
import Foundation
import HealthKit
import UIKit

struct HealthKitSyncConfiguration: Codable, Sendable {
    var selectedPersonUUID: String?
    var selectedPersonName: String?
    var initialSyncCompleted = false
    var lastSuccessfulSyncAt: Date?
    var estimatedRecordCount: Int?
    var estimatedRecordCountVersion: String?
    var syncedRecordCount = 0
    var currentSyncUploadedCount = 0
    var currentSampleTypeIdentifier: String?
    var sampleTypeAnchors: [String: Data] = [:]
}

enum HealthKitSyncPhase: String, Codable, Sendable {
    case notConfigured
    case needsPermission
    case ready
    case estimating
    case confirming
    case initialSyncing
    case incrementalSyncing
    case synced
    case failed
}

struct HealthKitSyncSnapshot: Sendable {
    var phase: HealthKitSyncPhase
    var statusText: String
    var detailText: String?
    var selectedPersonUUID: String?
    var selectedPersonName: String?
    var estimatedRecordCount: Int?
    var syncedRecordCount: Int
    var currentSyncUploadedCount: Int
    var lastSuccessfulSyncAt: Date?
    var currentSampleTypeIdentifier: String?
    var lastError: String?

    var personSelected: Bool {
        selectedPersonUUID != nil
    }

    var accessReady: Bool {
        estimatedRecordCount != nil || [.confirming, .initialSyncing, .incrementalSyncing, .synced].contains(phase)
    }

    var syncCompleted: Bool {
        phase == .synced || lastSuccessfulSyncAt != nil
    }

    var displayedTotalCount: Int {
        max(estimatedRecordCount ?? 0, syncedRecordCount)
    }

    var syncedCountText: String {
        let visibleCount = max(syncedRecordCount, currentSyncUploadedCount)
        let totalCount = max(displayedTotalCount, visibleCount)
        return "\(min(visibleCount, totalCount)) / \(totalCount) records synced"
    }
}

@MainActor
final class HealthKitSyncService: ObservableObject {
    static let shared = HealthKitSyncService()

    private static let refreshTaskIdentifier = "com.uncledoc.healthkit.refresh"
    private static let processingTaskIdentifier = "com.uncledoc.healthkit.processing"
    private static let syncEstimateSchemaVersion = "4"
    private static let syncBatchSize = 1000

    @Published private(set) var snapshot = HealthKitSyncSnapshot(
        phase: .notConfigured,
        statusText: "Connect HealthKit",
        detailText: "Choose a person, grant access, and UncleDoc will start syncing automatically.",
        selectedPersonUUID: nil,
        selectedPersonName: nil,
        estimatedRecordCount: nil,
        syncedRecordCount: 0,
        currentSyncUploadedCount: 0,
        lastSuccessfulSyncAt: nil,
        currentSampleTypeIdentifier: nil,
        lastError: nil
    )
    @Published private(set) var availablePeople: [RemotePerson] = []
    @Published private(set) var lastPeopleLoadError: String?

    private let healthKitManager = HealthKitManager.shared
    private let apiClient = APIClient.shared
    private let store = HealthKitSyncStore.shared
    private var isSyncing = false
    private var backgroundSyncTask: Task<Bool, Never>?

    var configuration: HealthKitSyncConfiguration {
        get { store.load() }
        set { store.save(newValue) }
    }

    func bootstrap() {
        invalidateEstimatedCountIfNeeded()
        refreshSnapshot(statusOverride: nil)
        Task {
            await loadAvailablePeopleIfNeeded()
            await refreshRemoteStatusIfPossible()
            await syncIfNeededOnForeground()
        }
    }

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                self.handleAppRefresh(task: task as! BGAppRefreshTask)
            }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                self.handleProcessing(task: task as! BGProcessingTask)
            }
        }
    }

    func scheduleBackgroundTasks() {
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)

        let processing = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(processing)
    }

    func cancelBackgroundSync() {
        backgroundSyncTask?.cancel()
    }

    func loadAvailablePeopleIfNeeded() async {
        guard availablePeople.isEmpty else { return }

        do {
            availablePeople = try await apiClient.fetchPeople()
            lastPeopleLoadError = nil
            applySelectedPersonNameIfPossible()
        } catch {
            lastPeopleLoadError = error.localizedDescription
            refreshSnapshot(statusOverride: error.localizedDescription)
        }
    }

    func selectPerson(_ person: RemotePerson) async {
        var config = configuration
        config.selectedPersonUUID = person.uuid
        config.selectedPersonName = person.name
        config.initialSyncCompleted = false
        config.lastSuccessfulSyncAt = nil
        config.estimatedRecordCount = nil
        config.currentSampleTypeIdentifier = nil
        config.syncedRecordCount = 0
        config.currentSyncUploadedCount = 0
        config.sampleTypeAnchors = [:]
        configuration = config
        refreshSnapshot(statusOverride: nil)
        await refreshRemoteStatusIfPossible()
        await prepareInitialSyncConfirmationAndStart()
    }

    func grantAccessAndStartIfPossible() async {
        do {
            try await healthKitManager.requestAuthorization()
            await prepareInitialSyncConfirmationAndStart()
        } catch {
            refreshSnapshot(statusOverride: error.localizedDescription, phase: .failed)
        }
    }

    func syncNow() async {
        if configuration.initialSyncCompleted {
            _ = await performIncrementalSync(trigger: "manual")
        } else {
            await prepareInitialSyncConfirmationAndStart(forceReestimate: true)
        }
    }

    func resetSync() async {
        var config = configuration
        config.initialSyncCompleted = false
        config.lastSuccessfulSyncAt = nil
        config.estimatedRecordCount = nil
        config.estimatedRecordCountVersion = nil
        config.syncedRecordCount = 0
        config.currentSyncUploadedCount = 0
        config.currentSampleTypeIdentifier = nil
        config.sampleTypeAnchors = [:]
        configuration = config

        refreshSnapshot(statusOverride: "Sync state reset. A full HealthKit sync will run again.", phase: .ready)
    }

    func syncIfNeededOnForeground() async {
        guard configuration.selectedPersonUUID != nil, !isSyncing else { return }

        if !configuration.initialSyncCompleted {
            _ = await performInitialSync(trigger: "foreground")
            return
        }

        _ = await performIncrementalSync(trigger: "foreground")
    }

    func loadDebugTypeCounts() async throws -> [(String, Int)] {
        try await healthKitManager.estimateSyncTypeCounts()
    }

    private func refreshRemoteStatusIfPossible() async {
        guard let personUUID = configuration.selectedPersonUUID else { return }

        do {
            let status = try await apiClient.fetchSyncStatus(personUUID: personUUID, deviceID: DeviceIdentityStore.shared.deviceID)
            var config = configuration
            config.lastSuccessfulSyncAt = status.sync.lastSuccessfulSyncAt ?? status.sync.lastSyncedAt ?? config.lastSuccessfulSyncAt
            config.syncedRecordCount = status.sync.syncedRecordCount
            if let personName = status.person.name as String? {
                config.selectedPersonName = personName
            }
            configuration = config
            refreshSnapshot(statusOverride: nil)
        } catch {
            // Keep local state as source of truth if the server status call fails.
        }
    }

    private func invalidateEstimatedCountIfNeeded() {
        var config = configuration
        guard config.estimatedRecordCountVersion != currentEstimateVersion else {
            return
        }

        config.estimatedRecordCount = nil
        config.estimatedRecordCountVersion = currentEstimateVersion
        config.syncedRecordCount = 0
        config.currentSyncUploadedCount = 0
        configuration = config
    }

    private var currentEstimateVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion)-\(buildVersion)-sync-\(Self.syncEstimateSchemaVersion)"
    }

    private func prepareInitialSyncConfirmationAndStart(forceReestimate: Bool = false) async {
        guard configuration.selectedPersonUUID != nil else {
            refreshSnapshot(statusOverride: nil, phase: .notConfigured)
            return
        }

        refreshSnapshot(statusOverride: "Counting Health records for the first sync...", phase: .estimating)

        var config = configuration
        if forceReestimate || config.estimatedRecordCount == nil {
            do {
                let rawCount = try await healthKitManager.estimateInitialRecordCount()
                config.estimatedRecordCount = rawCount
                config.estimatedRecordCountVersion = currentEstimateVersion
                configuration = config
            } catch {
                refreshSnapshot(statusOverride: error.localizedDescription, phase: .failed)
                return
            }
        }

        refreshSnapshot(statusOverride: "\(config.estimatedRecordCount ?? 0) records will now be synced.", phase: .confirming)
        _ = await performInitialSync(trigger: "setup")
    }

    private func performInitialSync(trigger: String) async -> Bool {
        guard !isSyncing, let personUUID = configuration.selectedPersonUUID else { return false }
        isSyncing = true
        defer { isSyncing = false }

        refreshSnapshot(statusOverride: "Starting initial HealthKit sync...", phase: .initialSyncing)

        do {
            try Task.checkCancellation()
            let deviceID = DeviceIdentityStore.shared.deviceID
            var resetConfig = configuration
            resetConfig.currentSyncUploadedCount = 0
            configuration = resetConfig
            let characteristicRecords = healthKitManager.characteristicSyncRecords(deviceID: deviceID)
            if !characteristicRecords.isEmpty {
                try Task.checkCancellation()
                try await upload(records: characteristicRecords, status: "syncing", phase: "characteristics", sampleType: "characteristics", completed: false)
            }

            for sampleType in healthKitManager.syncableSampleTypes {
                var localAnchor = configuration.sampleTypeAnchors[sampleType.identifier]

                while true {
                    try Task.checkCancellation()
                    refreshSnapshot(statusOverride: "Syncing \(sampleType.identifier)...", phase: .initialSyncing, currentSampleTypeIdentifier: sampleType.identifier)
                    let batch = try await healthKitManager.fetchAnchoredBatch(for: sampleType, anchorData: localAnchor, limit: Self.syncBatchSize)
                    localAnchor = batch.anchorData

                    if !batch.records.isEmpty {
                        try Task.checkCancellation()
                        try await upload(records: batch.records, status: "syncing", phase: trigger, sampleType: sampleType.identifier, completed: false)
                    }

                    var config = configuration
                    config.sampleTypeAnchors[sampleType.identifier] = localAnchor
                    config.currentSampleTypeIdentifier = sampleType.identifier
                    configuration = config

                    if !batch.hasMore {
                        break
                    }
                }
            }

            var config = configuration
            config.initialSyncCompleted = true
            config.lastSuccessfulSyncAt = Date()
            config.currentSyncUploadedCount = config.syncedRecordCount
            config.currentSampleTypeIdentifier = nil
            configuration = config

            try Task.checkCancellation()
            try await upload(records: [], status: "synced", phase: trigger, sampleType: nil, completed: true)
            refreshSnapshot(statusOverride: "HealthKit sync finished.", phase: .synced)
            scheduleBackgroundTasks()
            _ = personUUID
            return true
        } catch is CancellationError {
            handleInterruptedSync(status: "HealthKit sync paused. It will resume automatically.")
            return false
        } catch {
            var config = configuration
            config.currentSampleTypeIdentifier = nil
            configuration = config
            refreshSnapshot(statusOverride: error.localizedDescription, phase: .failed)
            return false
        }
    }

    private func performIncrementalSync(trigger: String) async -> Bool {
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }

        refreshSnapshot(statusOverride: "Checking for HealthKit changes...", phase: .incrementalSyncing)

        do {
            try Task.checkCancellation()
            let deviceID = DeviceIdentityStore.shared.deviceID
            var resetConfig = configuration
            resetConfig.currentSyncUploadedCount = 0
            configuration = resetConfig
            let characteristicRecords = healthKitManager.characteristicSyncRecords(deviceID: deviceID)
            if !characteristicRecords.isEmpty {
                try Task.checkCancellation()
                try await upload(records: characteristicRecords, status: "syncing", phase: trigger, sampleType: "characteristics", completed: false)
            }

            for sampleType in healthKitManager.syncableSampleTypes {
                var localAnchor = configuration.sampleTypeAnchors[sampleType.identifier]

                while true {
                    try Task.checkCancellation()
                    refreshSnapshot(statusOverride: "Checking \(sampleType.identifier)...", phase: .incrementalSyncing, currentSampleTypeIdentifier: sampleType.identifier)
                    let batch = try await healthKitManager.fetchAnchoredBatch(for: sampleType, anchorData: localAnchor, limit: Self.syncBatchSize)
                    localAnchor = batch.anchorData

                    if !batch.records.isEmpty {
                        try Task.checkCancellation()
                        try await upload(records: batch.records, status: "syncing", phase: trigger, sampleType: sampleType.identifier, completed: false)
                    }

                    var config = configuration
                    config.sampleTypeAnchors[sampleType.identifier] = localAnchor
                    config.currentSampleTypeIdentifier = sampleType.identifier
                    configuration = config

                    if !batch.hasMore {
                        break
                    }
                }
            }

            var config = configuration
            config.currentSampleTypeIdentifier = nil
            config.lastSuccessfulSyncAt = Date()
            config.currentSyncUploadedCount = 0
            configuration = config

            try Task.checkCancellation()
            try await upload(records: [], status: "synced", phase: trigger, sampleType: nil, completed: true)
            refreshSnapshot(statusOverride: "HealthKit is up to date.", phase: .synced)
            scheduleBackgroundTasks()
            return true
        } catch is CancellationError {
            handleInterruptedSync(status: "HealthKit sync paused. It will resume automatically.")
            return false
        } catch {
            var config = configuration
            config.currentSampleTypeIdentifier = nil
            configuration = config
            refreshSnapshot(statusOverride: error.localizedDescription, phase: .failed)
            return false
        }
    }

    private func handleInterruptedSync(status: String) {
        var config = configuration
        config.currentSampleTypeIdentifier = nil
        configuration = config
        refreshSnapshot(statusOverride: status, phase: defaultPhase(for: config))
    }

    private func upload(records: [HealthKitRecordPayload], status: String, phase: String, sampleType: String?, completed: Bool) async throws {
        guard let personUUID = configuration.selectedPersonUUID else {
            throw HealthKitSyncError.personNotSelected
        }

        let sync = try await apiClient.sync(
            HealthKitSyncRequest(
                personUUID: personUUID,
                deviceID: DeviceIdentityStore.shared.deviceID,
                status: status,
                phase: phase,
                batchCount: records.count,
                estimatedTotalCount: configuration.estimatedRecordCount,
                initialSyncCompleted: configuration.initialSyncCompleted,
                sampleType: sampleType,
                completed: completed,
                lastError: nil,
                records: records
            )
        )

        var config = configuration
        if !records.isEmpty {
            config.currentSyncUploadedCount += records.count
        }
        config.lastSuccessfulSyncAt = sync.lastSuccessfulSyncAt ?? sync.lastSyncedAt ?? config.lastSuccessfulSyncAt
        config.syncedRecordCount = max(sync.syncedRecordCount, config.currentSyncUploadedCount)
        configuration = config
    }

    private func refreshSnapshot(statusOverride: String?, phase: HealthKitSyncPhase? = nil, currentSampleTypeIdentifier: String? = nil) {
        let config = configuration
        let currentPhase = phase ?? defaultPhase(for: config)
        snapshot = HealthKitSyncSnapshot(
            phase: currentPhase,
            statusText: statusOverride ?? defaultStatusText(for: config, phase: currentPhase),
            detailText: defaultDetailText(for: config, phase: currentPhase),
            selectedPersonUUID: config.selectedPersonUUID,
            selectedPersonName: config.selectedPersonName,
            estimatedRecordCount: config.estimatedRecordCount,
            syncedRecordCount: config.syncedRecordCount,
            currentSyncUploadedCount: config.currentSyncUploadedCount,
            lastSuccessfulSyncAt: config.lastSuccessfulSyncAt,
            currentSampleTypeIdentifier: currentSampleTypeIdentifier ?? config.currentSampleTypeIdentifier,
            lastError: currentPhase == .failed ? statusOverride : nil
        )
    }

    private func applySelectedPersonNameIfPossible() {
        guard let uuid = configuration.selectedPersonUUID,
              let person = availablePeople.first(where: { $0.uuid == uuid }) else { return }

        var config = configuration
        config.selectedPersonName = person.name
        configuration = config
        refreshSnapshot(statusOverride: nil)
    }

    private func defaultPhase(for configuration: HealthKitSyncConfiguration) -> HealthKitSyncPhase {
        if configuration.selectedPersonUUID == nil { return .notConfigured }
        if !healthKitManager.isAvailable { return .failed }
        if !configuration.initialSyncCompleted { return .ready }
        return .synced
    }

    private func defaultStatusText(for configuration: HealthKitSyncConfiguration, phase: HealthKitSyncPhase) -> String {
        switch phase {
        case .notConfigured:
            return "Choose which UncleDoc person this device belongs to."
        case .ready:
            return "HealthKit is ready to sync."
        case .synced:
            return "HealthKit sync is configured."
        case .failed:
            return "HealthKit sync needs attention."
        default:
            return snapshot.statusText
        }
    }

    private func defaultDetailText(for configuration: HealthKitSyncConfiguration, phase: HealthKitSyncPhase) -> String? {
        switch phase {
        case .notConfigured:
            return "This device is linked to one UncleDoc person. Pick the person once and all synced Health data will belong there."
        case .ready:
            return configuration.selectedPersonName.map { "Ready to sync Health data into \($0)." }
        case .synced:
            return configuration.lastSuccessfulSyncAt.map { "Last successful sync: \($0.formatted())" }
        default:
            return snapshot.detailText
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundTasks()
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.cancelBackgroundSync()
            }
        }
        backgroundSyncTask = Task {
            guard !Task.isCancelled else { return false }
            await syncIfNeededOnForeground()
            return !Task.isCancelled
        }
        Task {
            let syncTask = await MainActor.run { self.backgroundSyncTask }
            let success = await syncTask?.value ?? false
            task.setTaskCompleted(success: success)
            await MainActor.run {
                self.backgroundSyncTask = nil
            }
        }
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleBackgroundTasks()
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.cancelBackgroundSync()
            }
        }
        backgroundSyncTask = Task { [weak self] in
            guard let self else { return false }
            if configuration.initialSyncCompleted {
                return await performIncrementalSync(trigger: "background")
            } else {
                return await performInitialSync(trigger: "background")
            }
        }
        Task {
            let syncTask = await MainActor.run { self.backgroundSyncTask }
            let success = await syncTask?.value ?? false
            task.setTaskCompleted(success: success)
            await MainActor.run {
                self.backgroundSyncTask = nil
            }
        }
    }
}

@MainActor
private final class HealthKitSyncStore {
    static let shared = HealthKitSyncStore()
    private let key = "uncledoc.healthkit.sync.configuration"

    func load() -> HealthKitSyncConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let configuration = try? JSONDecoder().decode(HealthKitSyncConfiguration.self, from: data) else {
            return HealthKitSyncConfiguration()
        }

        return configuration
    }

    func save(_ configuration: HealthKitSyncConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

@MainActor
private final class DeviceIdentityStore {
    static let shared = DeviceIdentityStore()
    private let key = "uncledoc.healthkit.device_id"

    var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }

        let newValue = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newValue, forKey: key)
        return newValue
    }
}

enum HealthKitSyncError: LocalizedError {
    case personNotSelected

    var errorDescription: String? {
        switch self {
        case .personNotSelected:
            return "Choose a person before syncing HealthKit data."
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }

        return stride(from: 0, to: count, by: size).map { index in
            Array(self[index..<Swift.min(index + size, count)])
        }
    }
}
