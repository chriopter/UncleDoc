import Foundation

struct RemotePerson: Decodable, Identifiable, Sendable {
    let uuid: String
    let name: String

    var id: String { uuid }
}

struct HealthKitRecordPayload: Codable, Sendable {
    let externalID: String
    let recordType: String
    let sourceName: String?
    let startAt: String
    let endAt: String?
    let payload: [String: String]

    enum CodingKeys: String, CodingKey {
        case externalID = "external_id"
        case recordType = "record_type"
        case sourceName = "source_name"
        case startAt = "start_at"
        case endAt = "end_at"
        case payload
    }
}

struct HealthKitSyncStatusResponse: Decodable, Sendable {
    struct PersonSummary: Decodable, Sendable {
        let uuid: String
        let name: String
    }

    struct SyncSummary: Decodable, Sendable {
        let status: String
        let lastSyncedAt: Date?
        let lastSuccessfulSyncAt: Date?
        let syncedRecordCount: Int
        let lastError: String?
        let details: [String: String]?

        enum CodingKeys: String, CodingKey {
            case status
            case lastSyncedAt = "last_synced_at"
            case lastSuccessfulSyncAt = "last_successful_sync_at"
            case syncedRecordCount = "synced_record_count"
            case lastError = "last_error"
            case details
        }
    }

    let person: PersonSummary
    let sync: SyncSummary
}

struct HealthKitSyncRequest: Encodable, Sendable {
    let personUUID: String
    let deviceID: String
    let status: String
    let phase: String
    let batchCount: Int
    let estimatedTotalCount: Int?
    let initialSyncCompleted: Bool
    let sampleType: String?
    let completed: Bool
    let lastError: String?
    let records: [HealthKitRecordPayload]

    enum CodingKeys: String, CodingKey {
        case personUUID = "person_uuid"
        case deviceID = "device_id"
        case status, phase, records, completed
        case batchCount = "batch_count"
        case estimatedTotalCount = "estimated_total_count"
        case initialSyncCompleted = "initial_sync_completed"
        case sampleType = "sample_type"
        case lastError = "last_error"
    }
}

final class APIClient: NSObject, @unchecked Sendable {
    static let shared = APIClient()

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private var baseURL: URL? {
        ServerURLStore.load()
    }

    func fetchPeople() async throws -> [RemotePerson] {
        struct Response: Decodable { let people: [RemotePerson] }
        return try await request(path: "ios/healthkit/people", method: "GET", body: Optional<Data>.none, responseType: Response.self).people
    }

    func fetchSyncStatus(personUUID: String, deviceID: String? = nil) async throws -> HealthKitSyncStatusResponse {
        var queryItems = [
            URLQueryItem(name: "person_uuid", value: personUUID)
        ]
        if let deviceID {
            queryItems.append(URLQueryItem(name: "device_id", value: deviceID))
        }

        var components = URLComponents()
        components.path = "ios/healthkit/status"
        components.queryItems = queryItems

        let path = components.string ?? "ios/healthkit/status?person_uuid=\(personUUID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? personUUID)"
        try await request(path: path, method: "GET", body: Optional<Data>.none, responseType: HealthKitSyncStatusResponse.self)
    }

    func sync(_ payload: HealthKitSyncRequest) async throws -> HealthKitSyncStatusResponse.SyncSummary {
        struct Response: Decodable {
            let sync: HealthKitSyncStatusResponse.SyncSummary
        }

        let body = try encoder.encode(payload)
        return try await request(path: "ios/healthkit/sync", method: "POST", body: body, responseType: Response.self).sync
    }

    private func request<Response: Decodable>(path: String, method: String, body: Data?, responseType: Response.Type) async throws -> Response {
        guard let baseURL else {
            throw APIClientError.serverNotConfigured
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw APIClientError.requestFailed(message)
        }

        return try decoder.decode(responseType, from: data)
    }
}

extension APIClient: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if TrustedCertificateStore.contains(challenge.protectionSpace) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

enum APIClientError: LocalizedError {
    case serverNotConfigured
    case invalidURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "Server URL is not configured."
        case .invalidURL:
            return "The server URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .requestFailed(let message):
            return message
        }
    }
}
