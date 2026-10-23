import Foundation
import Security

/// The tokens the app holds between launches for one signed-in session.
struct StoredSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var accountID: String
}

/// Persistence for the signed-in session. Abstracted so the view model can be
/// driven with an in-memory fake in previews/tests.
protocol TokenStoring {
    func load() -> StoredSession?
    func save(_ session: StoredSession)
    func clear()
}

/// Keychain-backed session storage. Tokens are sensitive, so they live in the
/// Keychain (not UserDefaults), reachable only after first unlock on this device.
struct KeychainTokenStore: TokenStoring {
    private let service = "dev.devmohd.bunnlist.auth"
    private let account = "session"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
