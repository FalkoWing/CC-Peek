#if os(macOS)
import Foundation

/// 写诊断日志到 ~/Library/Application Support/cc-peek/diagnostic.log.
/// 24 小时滚动 (每次写之前检查文件 mtime; 超过 24h 的旧文件归档/截断).
///
/// 写法选择 jsonl: 每行一条记录, 后续 UI 解析容易; 失败静默不抛.
///
/// iOS 端如需诊断日志, 后续单独实现一个沙箱版本.
public enum DiagnosticLogger {
    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    public struct Entry: Codable, Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let severity: Severity
        public let category: String
        public let message: String
        public let context: [String: String]

        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            severity: Severity,
            category: String,
            message: String,
            context: [String: String] = [:]
        ) {
            self.id = id
            self.timestamp = timestamp
            self.severity = severity
            self.category = category
            self.message = message
            self.context = context
        }
    }

    public static var fileURL: URL {
        AppPaths.appSupportDirectory.appendingPathComponent("diagnostic.log")
    }

    public static func log(
        _ severity: Severity,
        category: String,
        message: String,
        context: [String: String] = [:]
    ) {
        let entry = Entry(
            severity: severity,
            category: category,
            message: message,
            context: context
        )
        write(entry)
    }

    public static func info(_ category: String, _ message: String, context: [String: String] = [:]) {
        log(.info, category: category, message: message, context: context)
    }

    public static func warn(_ category: String, _ message: String, context: [String: String] = [:]) {
        log(.warning, category: category, message: message, context: context)
    }

    public static func error(_ category: String, _ message: String, context: [String: String] = [:]) {
        log(.error, category: category, message: message, context: context)
    }

    /// 读取最近 24 小时所有条目, 按时间倒序.
    public static func recentEntries() -> [Entry] {
        rotateIfNeeded()
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var entries: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let lineData = line.data(using: .utf8),
               let entry = try? decoder.decode(Entry.self, from: lineData) {
                entries.append(entry)
            }
        }
        // 24h 截断
        let cutoff = Date().addingTimeInterval(-86400)
        return entries.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp > $1.timestamp }
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - private

    private static let queue = DispatchQueue(label: "me.lifawei.ccpeek.diagnostic")

    private static func write(_ entry: Entry) {
        queue.sync {
            AppPaths.ensureAppSupportDirectory()
            rotateIfNeeded()

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard var data = try? encoder.encode(entry) else { return }
            data.append(0x0A)

            let path = fileURL.path
            let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard fd >= 0 else { return }
            data.withUnsafeBytes { buf in
                _ = Darwin.write(fd, buf.baseAddress, buf.count)
            }
            close(fd)
        }
    }

    /// 文件 mtime 超过 24 小时直接清空 (简化: 不做归档).
    private static func rotateIfNeeded() {
        let path = fileURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else {
            return
        }
        if Date().timeIntervalSince(mtime) > 86400 {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
#endif
