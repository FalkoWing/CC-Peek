import Foundation

/// 持久化已配对 Mac 主机的 displayName + 随机 pairing token.
/// displayName 只用于展示/发现匹配, 自动重连必须带 token 给 Mac 校验.
enum PairedHostStorage {
    struct PairedHost {
        let displayName: String
        let token: String
    }

    private static let nameKey = "paired.host.displayName"
    private static let tokenKey = "paired.host.token"

    static var pairedHost: PairedHost? {
        guard let displayName = KeychainStore.string(for: nameKey),
              let token = KeychainStore.string(for: tokenKey),
              !displayName.isEmpty,
              !token.isEmpty else {
            return nil
        }
        return PairedHost(displayName: displayName, token: token)
    }

    static var pairedHostName: String? {
        pairedHost?.displayName
    }

    static func savePaired(_ displayName: String, token: String) {
        guard !displayName.isEmpty, !token.isEmpty else { return }
        KeychainStore.setString(displayName, for: nameKey)
        KeychainStore.setString(token, for: tokenKey)
    }

    static func clear() {
        KeychainStore.remove(for: nameKey)
        KeychainStore.remove(for: tokenKey)
    }
}
