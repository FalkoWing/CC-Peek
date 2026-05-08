import Foundation
import AppKit
import ServiceManagement

/// 开机自启包装. 优先用 SMAppService.mainApp; 当其状态 .notFound 时
/// fallback 到老式 LaunchAgent plist —— 写一个 plist 到 ~/Library/LaunchAgents/
/// 由 launchd 在登录时启动. 这种方式不依赖签名等级, 跨 macOS 版本稳定.
@MainActor
enum LaunchAtLoginManager {
    private static let agentLabel = "com.ccpeek.mac.agent"
    private static let legacyAgentLabels = ["me.lifawei.ccpeek.agent"]
    private static let officialDeveloperIDAuthority = "Developer ID Application: Fawei Li (M7727NJV5J)"
    private static let officialTeamIdentifier = "M7727NJV5J"

    /// 当前实际生效的实现方式. UI 用来显示"用什么方式管的"
    enum Backend: String {
        case smAppService     // 系统登录项面板里能看到, Developer ID 签名时首选
        case launchAgent      // ~/Library/LaunchAgents/ plist, adhoc 也工作
    }

    static var preferredBackend: Backend {
        // SMAppService 报 .notFound 时直接走 LaunchAgent, 否则走 SMAppService
        if SMAppService.mainApp.status == .notFound {
            return .launchAgent
        }
        return .smAppService
    }

    static var isEnabled: Bool {
        switch preferredBackend {
        case .smAppService: return SMAppService.mainApp.status == .enabled
        case .launchAgent:  return launchAgentPlistExists()
        }
    }

    /// 始终可配置 (LaunchAgent 不挑签名). 留这个 API 是为了 UI 兼容.
    static var canConfigure: Bool { true }

    static var statusDescription: String {
        let backend = preferredBackend
        switch backend {
        case .smAppService:
            switch SMAppService.mainApp.status {
            case .notRegistered:    return String(localized: "未开启 (SMAppService)")
            case .enabled:          return String(localized: "已开启 (SMAppService)")
            case .requiresApproval: return String(localized: "需在系统设置允许")
            case .notFound:         return String(localized: "Launch Services 未识别")
            @unknown default:       return String(localized: "未知")
            }
        case .launchAgent:
            return launchAgentPlistExists() ? String(localized: "已开启 (LaunchAgent)") : String(localized: "未开启 (LaunchAgent)")
        }
    }

    static var hint: String {
        if isOfficialReleaseSignature {
            return ""
        }
        return String(localized: "当前 .app 不是正式 Developer ID 签名，系统登录项面板可能不接受。CC Peek 会写一个 LaunchAgent plist 到 ~/Library/LaunchAgents/ 自己管开机自启。")
    }

    static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        switch preferredBackend {
        case .smAppService:
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        case .launchAgent:
            return enabled ? installLaunchAgent() : removeLaunchAgent()
        }
    }

    // MARK: - LaunchAgent backend

    private static var isOfficialReleaseSignature: Bool {
        guard let details = codesignDetails(for: Bundle.main.bundleURL) else {
            return false
        }
        return details.contains("Authority=\(officialDeveloperIDAuthority)")
            && details.contains("TeamIdentifier=\(officialTeamIdentifier)")
            && !details.contains("Signature=adhoc")
    }

    private static func codesignDetails(for appURL: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=4", appURL.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static var launchAgentURL: URL {
        launchAgentURL(for: agentLabel)
    }

    private static func launchAgentURL(for label: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    private static func launchAgentPlistExists() -> Bool {
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            return true
        }
        return legacyAgentLabels.contains {
            FileManager.default.fileExists(atPath: launchAgentURL(for: $0).path)
        }
    }

    private static func appExecutablePath() -> String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    private static func installLaunchAgent() -> Result<Void, Error> {
        removeLegacyLaunchAgents()
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [appExecutablePath()],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]

        let url = launchAgentURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: url, options: .atomic)
            // 让 launchd 立刻接受 (下次登录自动启动; 也可以用 launchctl bootstrap, 但需要 uid)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func removeLaunchAgent() -> Result<Void, Error> {
        removeLegacyLaunchAgents()
        let url = launchAgentURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .success(())
        }
        do {
            try FileManager.default.removeItem(at: url)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func removeLegacyLaunchAgents() {
        for label in legacyAgentLabels {
            let url = launchAgentURL(for: label)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
