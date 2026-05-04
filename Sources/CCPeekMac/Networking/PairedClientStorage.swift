import Foundation
import Security

/// Mac 端已配对 iPhone client 的 displayName 列表 + Keychain token.
@MainActor
enum PairedClientStorage {
    private static let key = "paired.client.displayNames"
    private static let legacyTokenKey = "paired.client.tokensByDisplayName"
    private static let keychainService = "me.lifawei.ccpeek.paired-clients"

    static var paired: Set<String> {
        migrateLegacyTokensIfNeeded()
        return Set(storedDisplayNames())
    }

    static func add(_ displayName: String, token: String) {
        guard !displayName.isEmpty, !token.isEmpty else { return }
        migrateLegacyTokensIfNeeded()
        guard saveToken(token, for: displayName) else { return }
        var names = Set(storedDisplayNames())
        names.insert(displayName)
        saveDisplayNames(names)
    }

    static func remove(_ displayName: String) {
        migrateLegacyTokensIfNeeded()
        var names = Set(storedDisplayNames())
        names.remove(displayName)
        saveDisplayNames(names)
        deleteToken(for: displayName)
    }

    static func contains(_ displayName: String, token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        migrateLegacyTokensIfNeeded()
        return storedToken(for: displayName) == token
    }

    static func clearAll() {
        let legacyNames = Set(legacyTokensByDisplayName().keys)
        let names = Set(storedDisplayNames()).union(legacyNames)
        for displayName in names {
            deleteToken(for: displayName)
        }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
    }

    private static func storedDisplayNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private static func saveDisplayNames(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names).sorted(), forKey: key)
    }

    private static func legacyTokensByDisplayName() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: legacyTokenKey) as? [String: String] ?? [:]
    }

    private static func migrateLegacyTokensIfNeeded() {
        let legacy = legacyTokensByDisplayName()
        guard !legacy.isEmpty else { return }

        var names = Set(storedDisplayNames())
        var migratedAll = true
        for (displayName, token) in legacy {
            guard !displayName.isEmpty, !token.isEmpty else { continue }
            if saveToken(token, for: displayName) {
                names.insert(displayName)
            } else {
                migratedAll = false
            }
        }
        saveDisplayNames(names)
        if migratedAll {
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        }
    }

    private static func storedToken(for displayName: String) -> String? {
        var query = keychainQuery(for: displayName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func saveToken(_ token: String, for displayName: String) -> Bool {
        let data = Data(token.utf8)
        let query = keychainQuery(for: displayName)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteToken(for displayName: String) {
        _ = SecItemDelete(keychainQuery(for: displayName) as CFDictionary)
    }

    private static func keychainQuery(for displayName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: displayName,
        ]
    }
}
