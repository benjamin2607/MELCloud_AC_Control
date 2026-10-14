import Foundation
import Security

/// Persists the MELCloud session. Only the session token goes into the Keychain;
/// the password is used once for sign-in and never stored.
struct CredentialStore: Sendable {
    private let service = "io.github.benjamin2607.climatecontrol.melcloud"
    private let tokenAccount = "session-token"
    private let emailKey = "accountEmail"

    var email: String? { UserDefaults.standard.string(forKey: emailKey) }

    func token() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns false if the Keychain refused the item (the session would otherwise be lost silently).
    @discardableResult
    func save(token: String, email: String) -> Bool {
        SecItemDelete(baseQuery() as CFDictionary)
        var item = baseQuery()
        item[kSecValueData as String] = Data(token.utf8)
        // Never synced via iCloud and unavailable before the first unlock after boot.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "ClimateControl – MELCloud session"
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return false }
        UserDefaults.standard.set(email, forKey: emailKey)
        return true
    }

    func clearToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    func clearAll() {
        clearToken()
        UserDefaults.standard.removeObject(forKey: emailKey)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
    }
}
