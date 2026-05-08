import Foundation

/// Mac 端已配对 iPhone client 的 displayName 列表 + 本地 pairing token.
@MainActor
enum PairedClientStorage {
    private static let key = "paired.client.displayNames"
    private static let tokenKey = "paired.client.tokensByDisplayName"

    static var paired: Set<String> {
        let tokens = tokensByDisplayName()
        let names = Set(storedDisplayNames())
        if names.isEmpty {
            return Set(tokens.keys)
        }
        return names.intersection(tokens.keys)
    }

    static func add(_ displayName: String, token: String) {
        guard !displayName.isEmpty, !token.isEmpty else { return }
        guard saveToken(token, for: displayName) else { return }
        var names = Set(storedDisplayNames())
        names.insert(displayName)
        saveDisplayNames(names)
    }

    static func remove(_ displayName: String) {
        var names = Set(storedDisplayNames())
        names.remove(displayName)
        saveDisplayNames(names)
        deleteToken(for: displayName)
    }

    static func contains(_ displayName: String, token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return storedToken(for: displayName) == token
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private static func storedDisplayNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private static func saveDisplayNames(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names).sorted(), forKey: key)
    }

    private static func tokensByDisplayName() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: tokenKey) as? [String: String] ?? [:]
    }

    private static func storedToken(for displayName: String) -> String? {
        guard let token = tokensByDisplayName()[displayName], !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func saveToken(_ token: String, for displayName: String) -> Bool {
        var tokens = tokensByDisplayName()
        tokens[displayName] = token
        UserDefaults.standard.set(tokens, forKey: tokenKey)
        return true
    }

    private static func deleteToken(for displayName: String) {
        var tokens = tokensByDisplayName()
        tokens.removeValue(forKey: displayName)
        UserDefaults.standard.set(tokens, forKey: tokenKey)
    }
}
