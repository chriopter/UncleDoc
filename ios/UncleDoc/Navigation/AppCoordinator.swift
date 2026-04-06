import Foundation

// TODO: Replace ContentView with Turbo Native navigator
// - Add turbo-ios SPM dependency
// - Configure Navigator with server URL
// - Set up tab bar (Home, Baby, Log, Settings)
// - Load path configuration from /api/v1/turbo/ios/path_configuration.json

enum AppCoordinator {
    static let serverURL = URL(string: "https://uncledoc.example.com")!
}
