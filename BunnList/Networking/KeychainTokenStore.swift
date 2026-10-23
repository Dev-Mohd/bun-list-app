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

/// Session storage: the Keychain when it is available (signed builds), with a
/// UserDefaults fallback for unsigned dev/simulator builds where the Keychain has
/// no entitlement and writes fail. A signed production build always uses the
/// Keychain path and never touches the fallback.
struct KeychainTokenStore: TokenStoring {
    private let service = "dev.devmohd.bunnlist.auth"
    private let account = "session"
    private let defaultsKey = "dev.devmohd.bunnlist.session.fallback"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    // MARK: TokenStoring

    func load() -> StoredSession? {
        if let fromKeychain = loadKeychain() { return fromKeychain }
        return loadDefaults()
    }

    func save(_ session: StoredSession) {
        if saveKeychain(session) {
            clearDefaults() // keychain is the source of truth when it works
        } else {
            saveDefaults(session)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        clearDefaults()
    }

    // MARK: Keychain

    private func loadKeychain() -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    /// Returns true only if the token was actually written to the Keychain.
    private func saveKeychain(_ session: StoredSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    // MARK: UserDefaults fallback (unsigned dev/simulator builds only)

    private func loadDefaults() -> StoredSession? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    private func saveDefaults(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func clearDefaults() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
