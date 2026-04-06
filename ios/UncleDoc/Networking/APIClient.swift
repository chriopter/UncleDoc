import Foundation

class APIClient {
    static let shared = APIClient()

    private let baseURL = AppCoordinator.serverURL
    private var apiToken: String? {
        // TODO: Read from Keychain
        nil
    }

    // TODO: Implement:
    // - POST /api/v1/people/:id/healthkit_entries (bulk create)
    // - GET /api/v1/people (list people)
    // - GET /api/v1/people/:id/healthkit_entries/last_sync
}
