import AppKit
import CCPeekCore
import Foundation

enum FeedbackComposer {
    @MainActor
    static func presentFeedback() {
        let crash = latestCrashReport()
        let body = composeBody(crash: crash)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)

        if let crash {
            NSWorkspace.shared.activateFileViewerSelecting([crash])
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "反馈内容已复制到剪贴板")
        if crash != nil {
            alert.informativeText = String(localized: "最近一份崩溃日志已在 Finder 中标出。\n请把剪贴板内容粘贴到 support@ccpeek.com、GitHub issue 或任意聊天工具, 并附带 Finder 里高亮的 .ips 文件。")
        } else {
            alert.informativeText = String(localized: "未发现近期崩溃日志, 仅复制了基础诊断信息。\n请把剪贴板内容粘贴到 support@ccpeek.com、GitHub issue 或任意聊天工具。")
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "好的"))
        alert.addButton(withTitle: String(localized: "改用邮件发送"))

        if alert.runModal() == .alertSecondButtonReturn {
            openMail(body: body)
        }
    }

    private static func openMail(body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@ccpeek.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "CC Peek 反馈")),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func composeBody(crash: URL?) -> String {
        var lines = [
            String(localized: "请简单描述你遇到的问题："),
            "",
            "",
            "----",
            String(localized: "版本：\(versionString)"),
            String(localized: "系统：\(ProcessInfo.processInfo.operatingSystemVersionString)"),
            String(localized: "诊断日志：\(DiagnosticLogger.fileURL.path)")
        ]
        if let crash {
            lines.append(String(localized: "最近崩溃日志：\(crash.path)"))
        } else {
            lines.append(String(localized: "最近崩溃日志：未找到"))
        }
        return lines.joined(separator: "\n")
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "v\(short) (\(build))"
    }

    private static func latestCrashReport() -> URL? {
        let reports = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: reports,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .filter { url in
                let name = url.lastPathComponent
                return name.hasSuffix(".ips")
                    && (name.hasPrefix("CCPeekMac-") || name.hasPrefix("CC Peek-") || name.hasPrefix("CCPeek-"))
            }
            .sorted { lhs, rhs in
                modificationDate(lhs) > modificationDate(rhs)
            }
            .first
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
