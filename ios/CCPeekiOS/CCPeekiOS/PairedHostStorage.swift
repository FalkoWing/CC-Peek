import Foundation

/// 持久化已配对 Mac 主机的 displayName. iOS-1b 用 displayName 字符串严格匹配.
enum PairedHostStorage {
    private static let key = "paired.host.displayName"

    static var pairedHostName: String? {
        KeychainStore.string(for: key)
    }

    static func savePaired(_ displayName: String) {
        KeychainStore.setString(displayName, for: key)
    }

    static func clear() {
        KeychainStore.remove(for: key)
    }
}
