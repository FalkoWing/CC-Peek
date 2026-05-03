import Foundation

/// Mac 端已配对 iPhone client 的 displayName 列表. UserDefaults 存储.
/// (避开 adhoc 签名 + Keychain 首次访问的密码弹窗.)
@MainActor
enum PairedClientStorage {
    private static let key = "paired.client.displayNames"
    private static let tokenKey = "paired.client.tokensByDisplayName"

    static var paired: Set<String> {
        Set(tokensByDisplayName.keys)
    }

    static func add(_ displayName: String, token: String) {
        guard !displayName.isEmpty, !token.isEmpty else { return }
        var current = tokensByDisplayName
        current[displayName] = token
        saveTokens(current)
    }

    static func remove(_ displayName: String) {
        var current = tokensByDisplayName
        current.removeValue(forKey: displayName)
        saveTokens(current)
    }

    static func contains(_ displayName: String, token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return tokensByDisplayName[displayName] == token
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private static var tokensByDisplayName: [String: String] {
        UserDefaults.standard.dictionary(forKey: tokenKey) as? [String: String] ?? [:]
    }

    private static func saveTokens(_ tokens: [String: String]) {
        UserDefaults.standard.set(tokens, forKey: tokenKey)
        UserDefaults.standard.set(Array(tokens.keys), forKey: key)
    }
}
