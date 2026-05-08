import AppKit
import CCPeekCore

/// 把焦点切到指定终端窗口/tab. 按 PRD 3.2.2 的分级表行为:
///   ✅ 完整支持 (Terminal/iTerm2): 激活 app + 按 tty 定位到具体 tab
///   🟡 部分支持 (其他识别出 bundleId 的): 仅激活 app
///   ❌ 不支持 (terminal 为 nil): 不可切换
@MainActor
enum TerminalSwitcher {
    enum SwitchResult: Equatable {
        case ok
        case activatedAppOnly      // 终端 app 切到前台但没定位 tab
        case unsupported(reason: String)
        case failed(reason: String)
    }

    static func canSwitch(_ process: ClaudeProcess) -> Bool {
        process.terminal != nil
    }

    static func `switch`(to process: ClaudeProcess) -> SwitchResult {
        DiagnosticLogger.info("switch", "切换尝试", context: [
            "processId": process.id,
            "kind": process.terminal?.kind.rawValue ?? "nil",
            "tty": process.terminal?.tty ?? "nil",
            "appPID": process.terminal.map { "\($0.appPID)" } ?? "nil",
        ])

        guard let location = process.terminal else {
            return .unsupported(reason: String(localized: "未识别终端 app"))
        }

        // 先把 app 切前台. NSRunningApplication 比 AppleScript 更便宜也更稳.
        if let app = NSRunningApplication(processIdentifier: location.appPID) {
            app.activate(options: [])
        }

        switch location.kind {
        case .appleTerminal:
            return runAppleTerminalSwitch(tty: location.tty)
        case .iterm2:
            return runIterm2Switch(tty: location.tty)
        case .ghostty, .warp, .vscode, .unknown:
            DiagnosticLogger.info("switch", "终端不支持 tab 定位, 仅激活 app", context: [
                "kind": location.kind.rawValue,
            ])
            return .activatedAppOnly
        }
    }

    // MARK: - Terminal.app

    private static func runAppleTerminalSwitch(tty: String?) -> SwitchResult {
        guard let tty else {
            DiagnosticLogger.warn("switch", "Terminal.app: tty 为 nil, 仅激活 app")
            return .activatedAppOnly
        }
        // selected 之前选, frontmost 之后设, 避免部分 macOS 版本下顺序倒置导致 tab 没切到.
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) is "\(tty)" then
                        set selected of t to true
                        set frontmost of w to true
                        return "matched"
                    end if
                end repeat
            end repeat
            return "not_found"
        end tell
        """
        return runAppleScript(
            script,
            terminal: "Terminal.app",
            expectedTTY: tty,
            listCurrentTTYs: listAppleTerminalTTYs
        )
    }

    /// 没匹配到时调用, 把 Terminal.app 当前所有 tab 的 tty 列到日志, 方便对比.
    private static func listAppleTerminalTTYs() -> String? {
        let script = """
        tell application "Terminal"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (tty of t) & ","
                end repeat
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        guard let s = NSAppleScript(source: script) else { return nil }
        let result = s.executeAndReturnError(&err)
        if err != nil { return nil }
        return result.stringValue
    }

    // MARK: - iTerm2

    private static func runIterm2Switch(tty: String?) -> SwitchResult {
        guard let tty else {
            DiagnosticLogger.warn("switch", "iTerm2: tty 为 nil, 仅激活 app")
            return .activatedAppOnly
        }
        // iTerm2 模型: window > tab > session, tty 在 session 上.
        let script = """
        tell application "iTerm"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) is "\(tty)" then
                            select s
                            select t
                            tell w to select
                            return "matched"
                        end if
                    end repeat
                end repeat
            end repeat
            return "not_found"
        end tell
        """
        return runAppleScript(
            script,
            terminal: "iTerm2",
            expectedTTY: tty,
            listCurrentTTYs: nil
        )
    }

    // MARK: -

    private static func runAppleScript(
        _ source: String,
        terminal: String,
        expectedTTY: String?,
        listCurrentTTYs: (() -> String?)?
    ) -> SwitchResult {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            DiagnosticLogger.error("applescript", "AppleScript 编译失败", context: ["terminal": terminal])
            return .failed(reason: String(localized: "AppleScript 编译失败 (\(terminal))"))
        }
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? String(localized: "未知错误")
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            DiagnosticLogger.error("applescript", "AppleScript 执行失败", context: [
                "terminal": terminal,
                "code": "\(code)",
                "message": msg,
            ])
            // 1743 = TCC 拒绝, 用户没给自动化权限.
            if code == -1743 {
                return .failed(reason: String(localized: "缺少自动化权限. 请到 系统设置 > 隐私与安全性 > 自动化, 允许本程序控制 \(terminal)."))
            }
            return .failed(reason: String(localized: "\(terminal) AppleScript 执行失败: \(msg)"))
        }
        let returned = descriptor.stringValue ?? ""
        if returned == "matched" {
            DiagnosticLogger.info("switch", "\(terminal) tab 切换成功", context: ["tty": expectedTTY ?? ""])
            return .ok
        }
        // not_found: app 已经 activate 过了, tab 没切到.
        var ctx: [String: String] = [
            "terminal": terminal,
            "expectedTTY": expectedTTY ?? "nil",
            "applescriptReturn": returned,
        ]
        if let listCurrentTTYs, let allTTYs = listCurrentTTYs() {
            ctx["currentTTYs"] = allTTYs
        }
        DiagnosticLogger.warn("switch", "\(terminal) 未匹配到 tty, 仅激活 app", context: ctx)
        return .activatedAppOnly
    }
}
