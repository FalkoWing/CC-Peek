import Foundation
import CCPeekCore

/// 写入 / 清理 ~/.claude/settings.json 中的 cc-peek hook 配置.
///
/// 设计:
/// - `computePlan()` 不写文件, 只算"应用后是什么样", 给 UI 做 diff 预览;
/// - `apply(plan:)` 真正写入 (含备份);
/// - `install()` 是 CLI 路径, 算 plan + 立即 apply, 不弹 UI.
enum HookInstaller {
    static let markerKey = "_ccpeek_marker"
    static let markerValue = "com.ccpeek.mac"
    private static let legacyMarkerValues = ["me.lifawei.ccpeek"]

    static let subscribedEvents: [String] = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "Stop",
        "Notification",
        "SessionEnd",
    ]

    public static func settingsFileURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    /// .app 模式: bundle 内 CCPeekHook;  swift run 模式: 同级 CCPeekHook.
    static func hookBinaryPath() -> String {
        let selfPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let dir = (selfPath as NSString).deletingLastPathComponent
        return dir + "/CCPeekHook"
    }

    /// settings.json 的 command 字段会被 Claude Code 用 shell 跑, 路径含空格
    /// (如 /Applications/CC Peek.app/...) 时必须包双引号防止被 shell 切词.
    static func hookCommandString() -> String {
        return "\"\(hookBinaryPath())\""
    }

    /// 当前 settings.json 是否已安装本产品的 hook.
    static func isInstalled() -> Bool {
        guard let settings = readJSON(settingsFileURL()),
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            if groups.contains(where: groupContainsOurMarker) {
                return true
            }
        }
        return false
    }

    /// 验证 settings.json 中 6 类 event 都注册了指向当前 hook binary 的条目.
    /// 任一 event 缺失 / command 路径不一致 / 文件不存在 → false.
    /// 用于 HookHealthMonitor 周期性健康检查.
    static func validate() -> Bool {
        guard let settings = readJSON(settingsFileURL()),
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        let expectedCmd = hookCommandString()
        for event in subscribedEvents {
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            let ok = groups.contains { group in
                guard let inner = group["hooks"] as? [[String: Any]] else { return false }
                return inner.contains {
                    ($0[markerKey] as? String) == markerValue &&
                        ($0["command"] as? String) == expectedCmd
                }
            }
            if !ok { return false }
        }
        return true
    }

    // MARK: - Plan / Apply

    struct Plan: Equatable, Sendable {
        let existingText: String        // 当前 settings.json 全文 (不存在则 "")
        let targetText: String          // 应用后预期全文
        let backupPath: String?         // 应用时会创建的备份路径 (settings.json 不存在时为 nil)
        let hookCommandPath: String     // 即将写入的 hook 二进制路径
        let willCreateSettingsFile: Bool
        let isNoOp: Bool                // 当前已经是目标态, apply 也不会改变什么
    }

    static func computePlan() -> Plan {
        let url = settingsFileURL()
        let existingText: String
        let willCreateSettingsFile: Bool
        let backupPath: String?

        if FileManager.default.fileExists(atPath: url.path) {
            existingText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            willCreateSettingsFile = false
            let ts = Int(Date().timeIntervalSince1970)
            backupPath = url.appendingPathExtension("ccpeek-backup-\(ts)").path
        } else {
            existingText = ""
            willCreateSettingsFile = true
            backupPath = nil
        }

        let target = buildTarget(from: existingText)
        let isNoOp = (target == existingText)

        return Plan(
            existingText: existingText,
            targetText: target,
            backupPath: backupPath,
            hookCommandPath: hookBinaryPath(),
            willCreateSettingsFile: willCreateSettingsFile,
            isNoOp: isNoOp
        )
    }

    /// 应用 plan: 备份 + 写入. 返回 (success, errorMessage).
    @discardableResult
    static func apply(plan: Plan) -> (Bool, String?) {
        let url = settingsFileURL()

        // 备份
        if let backupPath = plan.backupPath, FileManager.default.fileExists(atPath: url.path) {
            let backupURL = URL(fileURLWithPath: backupPath)
            try? FileManager.default.removeItem(at: backupURL)
            do {
                try FileManager.default.copyItem(at: url, to: backupURL)
            } catch {
                return (false, String(localized: "备份 settings.json 失败: \(error.localizedDescription)"))
            }
        }

        // 写入
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try plan.targetText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return (false, String(localized: "写入 settings.json 失败: \(error.localizedDescription)"))
        }

        return (true, nil)
    }

    // MARK: - 旧 CLI 入口

    static func install() {
        let plan = computePlan()
        if let backupPath = plan.backupPath, !plan.isNoOp {
            print("[cc-peek] 即将备份 settings.json -> \(backupPath)")
        }
        let (ok, err) = apply(plan: plan)
        if ok {
            print("[cc-peek] hook 已安装 -> \(settingsFileURL().path)")
            print("[cc-peek] 二进制路径: \(plan.hookCommandPath)")
            print("[cc-peek] 订阅事件: \(subscribedEvents.joined(separator: ", "))")
        } else {
            print("[cc-peek] 安装失败: \(err ?? "?")")
        }
    }

    static func uninstall() {
        let url = settingsFileURL()
        guard var settings = readJSON(url) else {
            print("[cc-peek] 未找到 \(url.path),无需清理")
            return
        }
        guard var hooks = settings["hooks"] as? [String: Any] else {
            print("[cc-peek] settings.json 中未配置 hooks,无需清理")
            return
        }

        var removed = 0
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            let before = groups.count
            groups.removeAll { groupContainsOurMarker($0) }
            removed += before - groups.count
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            print("[cc-peek] settings.json 序列化失败")
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            print("[cc-peek] 已从 settings.json 移除 \(removed) 条 hook 条目")
        } catch {
            print("[cc-peek] 写入失败: \(error)")
        }
    }

    // MARK: - Internals

    private static func buildTarget(from existingText: String) -> String {
        var settings: [String: Any] = [:]
        if !existingText.isEmpty,
           let data = existingText.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = obj
        }

        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        for event in subscribedEvents {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.removeAll(where: groupContainsOurMarker)
            let newGroup: [String: Any] = [
                "matcher": "",
                "hooks": [
                    [
                        "type": "command",
                        "command": hookCommandString(),
                        markerKey: markerValue,
                    ]
                ]
            ]
            groups.append(newGroup)
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ), var text = String(data: data, encoding: .utf8) else {
            return existingText
        }
        if !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private static func groupContainsOurMarker(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains {
            guard let value = $0[markerKey] as? String else { return false }
            return value == markerValue || legacyMarkerValues.contains(value)
        }
    }
}
