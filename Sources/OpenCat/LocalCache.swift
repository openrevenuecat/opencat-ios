import Foundation
import Security

/// Keychain-based encrypted cache for CustomerInfo.
/// Survives app reinstalls. Thread-safe via actor isolation.
actor LocalCache {
    private static let serviceName = "dev.opencat.sdk"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Save CustomerInfo to the Keychain.
    func save(_ customerInfo: CustomerInfo) {
        guard let data = try? encoder.encode(customerInfo) else { return }
        let key = keychainKey(for: customerInfo.appUserId)

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Load CustomerInfo from the Keychain.
    func load(appUserId: String) -> CustomerInfo? {
        let key = keychainKey(for: appUserId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? decoder.decode(CustomerInfo.self, from: data)
    }

    /// Delete cached CustomerInfo.
    func delete(appUserId: String) {
        let key = keychainKey(for: appUserId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func keychainKey(for appUserId: String) -> String {
        return "\(Self.serviceName).\(appUserId).customerInfo"
    }
}
