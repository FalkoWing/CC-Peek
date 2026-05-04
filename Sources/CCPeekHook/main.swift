import Foundation
import CCPeekCore
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Quick-fail 原则
// 1. 读 stdin 上限 1MB，超过截断
// 2. 任何错误静默退出 (exit 0)，不向 stderr 输出
// 3. 不重试、不打印 usage
// 4. CC_PEEK_DEBUG=1 时额外写一份 hook.debug.log 方便 MVP 调试

let isDebug = ProcessInfo.processInfo.environment["CC_PEEK_DEBUG"] == "1"

// 读 stdin
let stdinData = FileHandle.standardInput.readDataToEndOfFile()

// 解析 raw payload(允许不是合法 JSON 对象,此时存为字符串)
let rawPayload: Any
if let obj = try? JSONSerialization.jsonObject(with: stdinData, options: [.fragmentsAllowed]) {
    rawPayload = obj
} else {
    rawPayload = String(data: stdinData, encoding: .utf8) ?? ""
}

// hook 进程的父 = Claude Code 进程 (或其内部 worker)
let claudePID = getppid()

// 在 hook 时刻就走完父链快照, 避免 watcher 消费时短命中间进程已退出.
let chain = ProcessChain.walk(from: claudePID)

// 用 claudePID 的 e_tdev 解析直接 shell 的 tty.
// Claude Code 进程的 tty 与产它的 shell 同一个, 直接拿 claudePID 的更稳.
let shellTTY = ProcessChain.ttyName(of: claudePID)

// 构造 envelope
guard let line = HookEnvelope.encodeLine(
    rawPayload: rawPayload,
    claudePID: claudePID,
    pidChain: chain,
    shellTTY: shellTTY
) else {
    exit(0)
}

// 确保目录
AppPaths.ensureAppSupportDirectory()

// 保护阈值: 主文件 > 100MB 时截断保留末尾 10MB (PRD 3.1.7)
let mainPath = AppPaths.eventsLogFile.path
if let attrs = try? FileManager.default.attributesOfItem(atPath: mainPath),
   let size = attrs[.size] as? Int, size > 100 * 1024 * 1024 {
    truncateTail(path: mainPath, keepBytes: 10 * 1024 * 1024)
}

// O_APPEND 原子写
let fd = open(mainPath, O_WRONLY | O_APPEND | O_CREAT, 0o600)
if fd >= 0 {
    _ = fchmod(fd, 0o600)
    line.withUnsafeBytes { buf in
        _ = write(fd, buf.baseAddress, buf.count)
    }
    close(fd)
}

// Debug 日志
if isDebug {
    let debugPath = AppPaths.hookDebugLog.path
    if let dfd = Optional(open(debugPath, O_WRONLY | O_APPEND | O_CREAT, 0o600)), dfd >= 0 {
        _ = fchmod(dfd, 0o600)
        line.withUnsafeBytes { buf in
            _ = write(dfd, buf.baseAddress, buf.count)
        }
        close(dfd)
    }
}

exit(0)

// MARK: - 辅助

func truncateTail(path: String, keepBytes: Int) {
    guard let handle = FileHandle(forReadingAtPath: path),
          let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attrs[.size] as? Int, size > keepBytes else {
        return
    }
    try? handle.seek(toOffset: UInt64(size - keepBytes))
    let tail = handle.readDataToEndOfFile()
    try? handle.close()

    // 找到第一个换行,从换行后开始保留(避免半行 JSON)
    var startIndex = 0
    if let nl = tail.firstIndex(of: 0x0A) {
        startIndex = nl + 1
    }
    let safeTail = tail.subdata(in: startIndex..<tail.count)

    let tmpPath = path + ".truncate.tmp"
    try? safeTail.write(to: URL(fileURLWithPath: tmpPath))
    _ = chmod(tmpPath, 0o600)
    _ = rename(tmpPath, path)
    _ = chmod(path, 0o600)
}
