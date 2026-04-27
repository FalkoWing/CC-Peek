import AppKit
import Darwin
import CCPeekCore

/// 在 hook 已经快照好的 PID 链上找终端 app.
///
/// hook 端用 ProcessChain.walk 一次性记录从 hook ppid 起的祖先 PID 列表,
/// watcher 这边对每个 PID 调 NSRunningApplication 取 bundleIdentifier,
/// 第一个匹配 TerminalKind 的进程即为终端 app, 链中前一跳是 shell/login.
@MainActor
enum ProcessTreeResolver {
    /// 只走链表, 不再自己 walk: 若 hook 已经把 PID chain 写到 envelope, 直接用之.
    /// 备用回落: 用 startingPID 现场 walk (适合 SessionStart 时 PID 仍活的场景).
    static func resolve(
        chain providedChain: [Int32]?,
        startingPID: Int32?,
        shellTTY: String? = nil,
        verbose: Bool = false
    ) -> TerminalLocation? {
        let chain: [Int32] = {
            if let c = providedChain, !c.isEmpty { return c }
            if let pid = startingPID { return ProcessChain.walk(from: pid) }
            return []
        }()

        if verbose { print("  chain: \(chain)") }

        for (i, pid) in chain.enumerated() {
            let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            if verbose { print("  [\(i)] pid=\(pid) bundleId=\(bundleId ?? "(nil)")") }
            if let kind = TerminalKind.from(bundleId: bundleId) {
                let shellPID = i > 0 ? chain[i - 1] : pid
                let tty = resolveTTY(
                    chain: chain,
                    terminalIndex: i,
                    shellPID: shellPID,
                    envelopeTTY: shellTTY,
                    verbose: verbose
                )
                if verbose { print("  ✅ kind=\(kind) appPID=\(pid) shellPID=\(shellPID) tty=\(tty ?? "nil")") }
                return TerminalLocation(
                    kind: kind,
                    appPID: pid,
                    shellPID: shellPID,
                    tty: tty
                )
            }
        }
        return nil
    }

    /// 解析 tty, 优先级:
    ///   1. envelope 里 hook 端记的 shellTTY (claudePID 当时还活的话最准)
    ///   2. 沿 chain 从 chain[0] 起找第一个有 tty 的 PID
    ///      (claude 自己若 detach 没 tty, 就退到 shell / login, 最终一定能命中,
    ///       因为 GUI terminal 下面挂的 shell 进程一定有 controlling terminal)
    /// 每个 PID 的尝试结果会写诊断日志, 复现一次就能看到链上 tty 分布.
    private static func resolveTTY(
        chain: [Int32],
        terminalIndex i: Int,
        shellPID: Int32,
        envelopeTTY: String?,
        verbose: Bool
    ) -> String? {
        if let t = envelopeTTY, !t.isEmpty {
            return t
        }

        var attempts: [String] = []
        // 不含 terminal app 自己 (chain[i]), 它显然没 controlling tty
        for j in 0..<i {
            let pid = chain[j]
            let tty = ProcessChain.ttyName(of: pid)
            attempts.append("pid=\(pid) tty=\(tty ?? "nil")")
            if let tty {
                DiagnosticLogger.info("resolve", "tty fallback 命中", context: [
                    "envelopeTTY": "nil",
                    "shellPID": "\(shellPID)",
                    "hitPID": "\(pid)",
                    "hitTTY": tty,
                    "chainAttempts": attempts.joined(separator: " | "),
                ])
                if verbose { print("  tty fallback hit pid=\(pid) tty=\(tty)") }
                return tty
            }
        }

        DiagnosticLogger.warn("resolve", "tty 解析失败: 整条 chain 都没拿到 tty", context: [
            "envelopeTTY": "nil",
            "shellPID": "\(shellPID)",
            "chainAttempts": attempts.joined(separator: " | "),
        ])
        return nil
    }
}
