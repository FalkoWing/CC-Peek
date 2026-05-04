import Foundation
import CCPeekCore

/// 监听 ~/Library/Application Support/cc-peek/events.jsonl 并消费.
///
/// 主路径: DispatchSource fsevent (PRD 3.1.3, ~50ms 延迟).
/// 兜底: 同时挂 5 秒低频 timer 兜底, 防 fsevent 漏触发 (rename 后偶发).
@MainActor
final class EventLogWatcher {
    private let store: ProcessStateStore
    private var source: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var fallbackTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "me.lifawei.ccpeek.eventwatcher")

    init(store: ProcessStateStore) {
        self.store = store
    }

    func start() {
        AppPaths.ensureAppSupportDirectory()
        ensureMainFileExists()
        // 启动即回放积压事件 (app 曾离线时 hook 持续 append).
        processPending()
        setupWatcher()
        startFallbackTimer()
    }

    func stop() {
        cancelWatcher()
        fallbackTimer?.cancel()
        fallbackTimer = nil
    }

    // MARK: - fsevent

    private func setupWatcher() {
        let path = AppPaths.eventsLogFile.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )

        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            Task { @MainActor in
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.restart()
                } else {
                    self.processPending()
                }
            }
        }

        source = src
        src.resume()
    }

    private func restart() {
        cancelWatcher()
        ensureMainFileExists()
        setupWatcher()
        processPending()
    }

    private func cancelWatcher() {
        source?.cancel()
        source = nil
        if watchedFD >= 0 {
            close(watchedFD)
            watchedFD = -1
        }
    }

    // MARK: - 兜底 timer (低频)

    private func startFallbackTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.processPending()
            }
        }
        t.resume()
        fallbackTimer = t
    }

    private func ensureMainFileExists() {
        let path = AppPaths.eventsLogFile.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(
                atPath: path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        } else {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path
            )
        }
    }

    // MARK: - Rename + consume

    private func processPending() {
        let mainFile = AppPaths.eventsLogFile
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: mainFile.path),
              let size = attrs[.size] as? Int, size > 0 else {
            return
        }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let processing = AppPaths.appSupportDirectory
            .appendingPathComponent("events.processing.\(ts).jsonl")

        do {
            try FileManager.default.moveItem(at: mainFile, to: processing)
        } catch {
            return
        }

        ensureMainFileExists()

        defer {
            try? FileManager.default.removeItem(at: processing)
        }

        guard let data = try? Data(contentsOf: processing) else { return }

        var events: [ParsedHookEvent] = []
        for lineData in splitLines(data) {
            guard !lineData.isEmpty else { continue }
            if let event = HookEnvelope.parseLine(lineData) {
                events.append(event)
            }
        }

        if !events.isEmpty {
            store.ingestBatch(events)
        }
    }

    private func splitLines(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        for i in data.indices where data[i] == 0x0A {
            if i > start {
                lines.append(data.subdata(in: start..<i))
            }
            start = data.index(after: i)
        }
        if start < data.endIndex {
            lines.append(data.subdata(in: start..<data.endIndex))
        }
        return lines
    }
}
