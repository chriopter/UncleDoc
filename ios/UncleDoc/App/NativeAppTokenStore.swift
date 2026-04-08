import Foundation
import Security

enum NativeAppTokenStore {
    private static let service = "com.uncledoc.native-auth"

    static func token(for serverURL: URL?) -> String? {
        guard let account = account(for: serverURL, suffix: "token") else { return nil }
        return read(account: account)
    }

    static func save(token: String, email: String?, for serverURL: URL) {
        write(token, account: account(for: serverURL, suffix: "token")!)

        if let email, !email.isEmpty {
            write(email, account: account(for: serverURL, suffix: "email")!)
        }
    }

    static func clear(for serverURL: URL?) {
        guard let serverURL else { return }

        delete(account: account(for: serverURL, suffix: "token")!)
        delete(account: account(for: serverURL, suffix: "email")!)
    }

    private static func account(for serverURL: URL?, suffix: String) -> String? {
        guard let serverURL else { return nil }
        return "\(serverURL.absoluteString.lowercased())::\(suffix)"
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
          var createQuery = query
          createQuery.merge(attributes) { _, new in new }
          SecItemAdd(createQuery as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
