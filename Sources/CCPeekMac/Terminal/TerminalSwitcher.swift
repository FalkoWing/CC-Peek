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
        guard let location = process.terminal else {
            return .unsupported(reason: "未识别终端 app")
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
            return .activatedAppOnly
        }
    }

    // MARK: - Terminal.app

    private static func runAppleTerminalSwitch(tty: String?) -> SwitchResult {
        guard let tty else {
            return .activatedAppOnly
        }
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) is "\(tty)" then
                        set frontmost of w to true
                        set selected of t to true
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        return runAppleScript(script, terminal: "Terminal.app")
    }

    // MARK: - iTerm2

    private static func runIterm2Switch(tty: String?) -> SwitchResult {
        guard let tty else {
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
                            tell w to set index to 1
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        return runAppleScript(script, terminal: "iTerm2")
    }

    // MARK: -

    private static func runAppleScript(_ source: String, terminal: String) -> SwitchResult {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            DiagnosticLogger.error("applescript", "AppleScript 编译失败", context: ["terminal": terminal])
            return .failed(reason: "AppleScript 编译失败 (\(terminal))")
        }
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "未知错误"
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            DiagnosticLogger.error("applescript", "AppleScript 执行失败", context: [
                "terminal": terminal,
                "code": "\(code)",
                "message": msg,
            ])
            // 1743 = TCC 拒绝, 用户没给自动化权限.
            if code == -1743 {
                return .failed(reason: "缺少自动化权限. 请到 系统设置 > 隐私与安全性 > 自动化, 允许本程序控制 \(terminal).")
            }
            return .failed(reason: "\(terminal) AppleScript 执行失败: \(msg)")
        }
        return .ok
    }
}
