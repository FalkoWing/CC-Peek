import AppKit
import CCPeekCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var eventWatcher: EventLogWatcher?
    private var pruneTimer: DispatchSourceTimer?
    private var transportBridge: HostTransportBridge?
    private let store = ProcessStateStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 子命令分发
        let args = CommandLine.arguments
        if args.contains("--install-hook") {
            HookInstaller.install()
            NSApp.terminate(nil)
            return
        }
        if args.contains("--uninstall-hook") {
            HookInstaller.uninstall()
            NSApp.terminate(nil)
            return
        }
        if args.contains("--print-hook-path") {
            print(HookInstaller.hookBinaryPath())
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--debug-tree"), i + 1 < args.count, let pid = Int32(args[i + 1]) {
            print("Resolving tree from pid=\(pid):")
            let result = ProcessTreeResolver.resolve(chain: nil, startingPID: pid, verbose: true)
            print("Result: \(String(describing: result))")
            NSApp.terminate(nil)
            return
        }

        AppPaths.ensureAppSupportDirectory()

        statusBarController = StatusBarController(store: store)

        let watcher = EventLogWatcher(store: store)
        eventWatcher = watcher
        watcher.start()

        // M3.C: 启动 host transport. MPC 第一次广告会触发"本地网络"权限弹窗;
        // 拒绝后下次启动可在系统设置里恢复, 不阻塞菜单栏功能.
        let bridge = HostTransportBridge(store: store)
        transportBridge = bridge
        bridge.start()

        // 首次启动展示引导. 已配置过的用户启动时不再弹.
        if !OnboardingWindowController.hasCompleted() {
            OnboardingWindowController.show()
        }

        // 启动回放完先 prune 一次, 然后 30 秒一次. 探活成本很低 (sysctl).
        store.pruneDead()
        startPruneTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventWatcher?.stop()
        pruneTimer?.cancel()
        transportBridge?.stop()
    }

    private func startPruneTimer() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .seconds(30), repeating: .seconds(30))
        t.setEventHandler { [weak self] in
            self?.store.pruneDead()
        }
        t.resume()
        pruneTimer = t
    }
}
