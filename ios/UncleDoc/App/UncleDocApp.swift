import SwiftUI

@main
struct UncleDocApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    HealthKitSyncService.shared.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await HealthKitSyncService.shared.syncIfNeededOnForeground()
                    }
                }
        }
    }
}
