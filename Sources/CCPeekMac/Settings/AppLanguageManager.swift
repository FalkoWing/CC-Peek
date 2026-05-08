import AppKit
import Foundation

// 通过修改 UserDefaults 的 AppleLanguages 实现 in-app 语言切换.
// Mac 端切换后会自动 relaunch 让改动生效.

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .zhHans: return "简体中文"
        case .en:     return "English"
        }
    }
}

enum AppLanguageManager {
    private static let key = "AppleLanguages"

    static var current: AppLanguage {
        guard
            let arr = UserDefaults.standard.array(forKey: key) as? [String],
            let first = arr.first?.lowercased()
        else {
            return .system
        }
        if first.hasPrefix("zh") { return .zhHans }
        if first.hasPrefix("en") { return .en }
        return .system
    }

    static func set(_ lang: AppLanguage) {
        let defaults = UserDefaults.standard
        if lang == .system {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set([lang.rawValue], forKey: key)
        }
        defaults.synchronize()
    }

    /// 切换语言后通过 `open -n` 拉一个新实例并 terminate 当前进程, 让 Bundle 加载新 locale.
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
