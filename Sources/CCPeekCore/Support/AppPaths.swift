#if os(macOS)
import Foundation

/// Mac 端固定路径集合. iOS 端有自己的沙箱目录, 不复用此模块.
public enum AppPaths {
    public static var appSupportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent("cc-peek", isDirectory: true)
    }

    public static var eventsLogFile: URL {
        appSupportDirectory.appendingPathComponent("events.jsonl")
    }

    public static var hookDebugLog: URL {
        appSupportDirectory.appendingPathComponent("hook.debug.log")
    }

    public static var archiveDirectory: URL {
        appSupportDirectory.appendingPathComponent("events.archive", isDirectory: true)
    }

    @discardableResult
    public static func ensureAppSupportDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }
}
#endif
