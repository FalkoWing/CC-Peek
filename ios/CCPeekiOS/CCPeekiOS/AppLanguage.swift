import Foundation

// 通过修改 UserDefaults 的 AppleLanguages 实现 in-app 语言切换.
// 改动需要重启 app 才生效 (iOS 不允许程序自杀, 只能提示用户手动 kill).

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
        guard let first = appLanguageCodes?.first?.lowercased() else {
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

    private static var appLanguageCodes: [String]? {
        guard
            let bundleID = Bundle.main.bundleIdentifier,
            let domain = UserDefaults.standard.persistentDomain(forName: bundleID)
        else {
            return nil
        }
        return domain[key] as? [String]
    }
}
