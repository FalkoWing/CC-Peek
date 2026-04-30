import Foundation

/// Mac 端已配对 iPhone client 的 displayName 列表. UserDefaults 存储.
/// (避开 adhoc 签名 + Keychain 首次访问的密码弹窗.)
@MainActor
enum PairedClientStorage {
    private static let key = "paired.client.displayNames"

    static var paired: Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(arr)
    }

    static func add(_ displayName: String) {
        var current = paired
        current.insert(displayName)
        UserDefaults.standard.set(Array(current), forKey: key)
    }

    static func remove(_ displayName: String) {
        var current = paired
        current.remove(displayName)
        UserDefaults.standard.set(Array(current), forKey: key)
    }

    static func contains(_ displayName: String) -> Bool {
        paired.contains(displayName)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
