import Foundation
import Combine
import CCPeekCore

@MainActor
final class ProcessStateStore: ObservableObject {
    @Published private(set) var processes: [ClaudeProcess] = []

    private var bySession: [String: ClaudeProcess] = [:]

    func ingest(_ event: ParsedHookEvent) {
        ingestBatch([event])
    }

    func ingestBatch(_ events: [ParsedHookEvent]) {
        for ev in events {
            guard let newState = Self.map(
                eventName: ev.eventName,
                notificationType: ev.notificationType,
                message: ev.message
            ) else {
                continue
            }

            if newState == .completed {
                bySession.removeValue(forKey: ev.sessionId)
                continue
            }

            var proc = bySession[ev.sessionId] ?? ClaudeProcess(
                id: ev.sessionId,
                name: Self.deriveName(cwd: ev.cwd, existing: bySession),
                state: newState,
                startedAt: ev.timestamp,
                stateChangedAt: ev.timestamp,
                cwd: ev.cwd,
                claudePID: ev.claudePID
            )

            if proc.state != newState {
                proc.state = newState
                proc.stateChangedAt = ev.timestamp
            }
            if proc.cwd == nil, let cwd = ev.cwd {
                proc.cwd = cwd
            }
            if proc.claudePID == nil, let pid = ev.claudePID {
                proc.claudePID = pid
            }

            // 终端尚未识别 → 用 envelope 里的 PID chain 解析.
            // hook 时刻就快照好链路, watcher 这边即使过了一段时间也能可靠拿到 GUI app PID.
            if proc.terminal == nil {
                proc.terminal = ProcessTreeResolver.resolve(
                    chain: ev.pidChain,
                    startingPID: ev.claudePID,
                    shellTTY: ev.shellTTY
                )
            }

            bySession[ev.sessionId] = proc
        }
        publishSnapshot()
    }

    private func publishSnapshot() {
        processes = bySession.values.sorted { $0.startedAt < $1.startedAt }
    }

    /// 移除已死的孤儿进程 (Claude Code 崩溃/被 kill / Ctrl-C 退出时不会触发 SessionEnd 事件).
    /// 探活策略 (按可靠性排序):
    ///   1. 有 claudePID 时, sysctl 探这个 PID; Claude 进程死了 session 必死.
    ///      关键: 不能只看 shellPID — 用户 Ctrl-C 退出 Claude 但保留 tab 是常态,
    ///      此时 shell 还活但 Claude 已死, 旧 session 必须清.
    ///   2. 没 claudePID 时回退到 shellPID 探活 (兼容老版本 hook 没写 claude_pid 的情况).
    ///   3. 都没有时, 等 staleAfter 没新事件再清.
    func pruneDead(staleAfter: TimeInterval = 300) {
        let now = Date()
        var toRemove: [(sid: String, reason: String)] = []

        for (sid, proc) in bySession {
            if let claudePID = proc.claudePID {
                if ProcessChain.parentPID(of: claudePID) == nil {
                    toRemove.append((sid, "claude pid \(claudePID) 已退出"))
                }
                continue
            }
            if let shell = proc.terminal?.shellPID {
                if ProcessChain.parentPID(of: shell) == nil {
                    toRemove.append((sid, "shell pid \(shell) 已退出"))
                }
            } else {
                if now.timeIntervalSince(proc.stateChangedAt) > staleAfter {
                    toRemove.append((sid, "无 terminal 信息且 \(Int(staleAfter))s 内无新事件"))
                }
            }
        }

        guard !toRemove.isEmpty else { return }
        for (sid, reason) in toRemove {
            DiagnosticLogger.info("prune", "移除孤儿 session", context: ["session_id": sid, "reason": reason])
            bySession.removeValue(forKey: sid)
        }
        publishSnapshot()
    }

    // MARK: - 规则

    /// PRD 3.1.5 hook → 状态机.
    /// Notification 事件: 优先用真实 schema 里的 notification_type 字段
    /// (实测值如 "permission_prompt"); 退化时再用 message 启发式.
    static func map(eventName: String, notificationType: String?, message: String?) -> ProcessState? {
        switch eventName {
        case "SessionStart":
            return .active
        case "UserPromptSubmit", "PreToolUse":
            return .active
        case "Stop":
            return .waitingInput
        case "Notification":
            if let nt = notificationType?.lowercased(), nt.contains("permission") {
                return .waitingPermission
            }
            if let msg = message?.lowercased(), msg.contains("permission") {
                return .waitingPermission
            }
            return .waitingInput
        case "SessionEnd":
            return .completed
        default:
            return nil
        }
    }

    /// 目录名 + #N (同目录多进程时加序号). PRD 3.2.5 降级规则.
    static func deriveName(cwd: String?, existing: [String: ClaudeProcess]) -> String {
        let base: String = {
            guard let cwd, let last = cwd.split(separator: "/").last, !last.isEmpty else {
                return "claude"
            }
            return String(last)
        }()
        let occupied = Set(existing.values.map(\.name))
        if !occupied.contains(base) { return base }

        var suffix = 2
        while occupied.contains("\(base) #\(suffix)") {
            suffix += 1
        }
        return "\(base) #\(suffix)"
    }

    private static func basename(_ path: String) -> String? {
        path.split(separator: "/").last.map(String.init)
    }
}
