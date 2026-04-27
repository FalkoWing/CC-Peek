#if os(macOS)
import Foundation
import Darwin

/// 走 sysctl KERN_PROC_PID 父链, 返回从起点 PID 一路到 launchd (PID 1) 之间的 PID 列表
/// (含起点, 不含 1). 失败/链路中断时返回已收集到的部分.
///
/// 设计目的: 在 hook 进程退出前快照整条祖先链, envelope 里携带这份链表;
/// Mac app 消费时不依赖任何进程是否仍存活——GUI 终端 app (在链尾附近) 寿命远长于 hook,
/// 由 NSRunningApplication 仍能在 watcher 侧准确识别.
///
/// iOS 沙箱不允许跨进程 sysctl, 该模块仅 macOS 可用.
public enum ProcessChain {
    public static func walk(from startingPID: Int32, maxHops: Int = 32) -> [Int32] {
        var chain: [Int32] = []
        var current = startingPID
        for _ in 0..<maxHops {
            guard current > 1 else { break }
            chain.append(current)
            guard let ppid = parentPID(of: current), ppid != current else { break }
            current = ppid
        }
        return chain
    }

    public static func parentPID(of pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = mib.withUnsafeMutableBufferPointer { ptr in
            sysctl(ptr.baseAddress, UInt32(ptr.count), &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    public static func ttyName(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = mib.withUnsafeMutableBufferPointer { ptr in
            sysctl(ptr.baseAddress, UInt32(ptr.count), &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        var buf = [CChar](repeating: 0, count: 128)
        let ptr = devname_r(dev, S_IFCHR, &buf, 128)
        guard let ptr, let name = String(validatingUTF8: ptr), !name.isEmpty, name != "??" else {
            return nil
        }
        return "/dev/" + name
    }
}
#endif
