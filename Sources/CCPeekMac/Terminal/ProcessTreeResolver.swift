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
                let tty = shellTTY ?? ProcessChain.ttyName(of: shellPID)
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
}
