import Foundation

/// events.jsonl 里每一行的结构。
///
/// 包 envelope 的目的：Claude Code 的 hook payload schema 可能变化，envelope 提供稳定的
/// recorded_at 时间戳和 raw 包裹，上层解析时始终能拿到"什么时候收到、原文是什么"。
public enum HookEnvelope {
    /// Hook 端在写 events.jsonl 时使用。返回的是一行 JSON 文本，已包含末尾换行符。
    ///
    /// - claudePID: hook 进程的父 PID (= Claude Code 进程或其内部子进程).
    /// - pidChain: 从 claudePID 起走父链得到的 PID 列表 (含起点, 不含 launchd).
    ///   pidChain 在 hook 时刻一次性快照, 避免 watcher 消费时 PID 已退出.
    /// - shellTTY: 直接产 Claude Code 的 shell 的 tty (如 "/dev/ttys001"),
    ///   AppleScript 切 tab 时按这个匹配.
    public static func encodeLine(
        rawPayload: Any,
        recordedAt: Date = Date(),
        claudePID: Int32? = nil,
        pidChain: [Int32]? = nil,
        shellTTY: String? = nil
    ) -> Data? {
        var envelope: [String: Any] = [
            "recorded_at": recordedAt.timeIntervalSince1970,
            "raw": rawPayload,
        ]
        if let pid = claudePID {
            envelope["claude_pid"] = Int(pid)
        }
        if let pidChain {
            envelope["pid_chain"] = pidChain.map(Int.init)
        }
        if let shellTTY {
            envelope["shell_tty"] = shellTTY
        }
        guard JSONSerialization.isValidJSONObject(envelope),
              var data = try? JSONSerialization.data(withJSONObject: envelope, options: []) else {
            return nil
        }
        data.append(0x0A) // "\n"
        return data
    }

    /// Mac app 端解析单行 envelope。
    public static func parseLine(_ data: Data) -> ParsedHookEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let recordedAt = (obj["recorded_at"] as? Double) ?? Date().timeIntervalSince1970
        let claudePID = (obj["claude_pid"] as? Int).map { Int32($0) }
        let pidChain = (obj["pid_chain"] as? [Int])?.map { Int32($0) }
        let shellTTY = obj["shell_tty"] as? String
        let raw = obj["raw"] as? [String: Any] ?? [:]

        let eventName = (raw["hook_event_name"] as? String)
            ?? (raw["eventName"] as? String)
            ?? ""
        let sessionId = (raw["session_id"] as? String)
            ?? (raw["sessionId"] as? String)
            ?? ""
        let cwd = raw["cwd"] as? String
        let message = raw["message"] as? String
        let notificationType = raw["notification_type"] as? String

        guard !eventName.isEmpty, !sessionId.isEmpty else {
            return nil
        }

        return ParsedHookEvent(
            eventName: eventName,
            sessionId: sessionId,
            cwd: cwd,
            message: message,
            notificationType: notificationType,
            claudePID: claudePID,
            pidChain: pidChain,
            shellTTY: shellTTY,
            timestamp: Date(timeIntervalSince1970: recordedAt)
        )
    }
}
