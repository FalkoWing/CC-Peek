import AppKit
import CCPeekCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var eventWatcher: EventLogWatcher?
    private var pruneTimer: DispatchSourceTimer?
    private var transportBridge: HostTransportBridge?
    private let store = ProcessStateStore()

    /// applicationDidFinishLaunching 完成后置 true，用于屏蔽启动过程中 didBecomeActive 的"假触发"。
    private var bootstrapped = false
    /// 被动触发（didBecomeActive / reopen / launch）共享的去抖窗口，避免 Spotlight 同时触发
    /// 两个 hook 时第二次 toggle 关掉刚弹出的窗口。主动触发（热键 / 点 statusItem）不受影响。
    private var passiveTriggerSuppressUntil: Date = .distantPast

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

        // M3.C: 启动 host transport. MPC 第一次广告会触发"本地网络"权限弹窗;
        // 拒绝后下次启动可在系统设置里恢复, 不阻塞菜单栏功能.
        let bridge = HostTransportBridge(store: store)
        transportBridge = bridge
        bridge.start()

        // StatusBarController 订阅 bridge.connectedPeerCount，bridge 必须先创建
        statusBarController = StatusBarController(store: store, bridge: bridge)

        let watcher = EventLogWatcher(store: store)
        eventWatcher = watcher
        watcher.start()

        // 首次启动展示引导. 已配置过的用户启动时不再弹.
        if !OnboardingWindowController.hasCompleted() {
            OnboardingWindowController.show()
        }

        // 启动回放完先 prune 一次, 然后 30 秒一次. 探活成本很低 (sysctl).
        store.pruneDead()
        startPruneTimer()

        // MacUI-2.5 Dashboard 多入口：监听 app 重新激活（Spotlight / Launchpad / open .app）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        // MacUI-2.5 全局热键：主动触发，不走去抖（按热键关 panel 应该立即生效）
        // 通用设置里的"快捷键在鼠标位置打开"开关 → 只影响热键路径, 不影响点 statusItem / launch 弹.
        KeyboardShortcuts.onKeyDown(for: .togglePeek) { [weak self] in
            let atMouse = UserDefaults.standard.bool(forKey: DashboardPresenter.shortcutOpensAtMouseKey)
            self?.statusBarController?.presenter.toggle(preferMouseOrigin: atMouse)
        }

        bootstrapped = true

        // 首次启动 / 退出后重新打开 app 时，主动弹一次主页面。
        // 不在 onboarding 期间（首次配置流程占据视线，不要叠 panel）。
        // 延迟 0.2s 给 NSStatusItem 的 button.window 时间 layout 完成,
        // 否则 panelOrigin 拿到 frame=(0,0,1,1) 会算出左上角落点 (panelOrigin 也加了 sanity check 兜底).
        // 同时让出 runloop 给可能到来的 didBecomeActive 先到 (被去抖拦下避免抖动).
        if !OnboardingWindowController.isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.triggerPassive(reason: "launch")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventWatcher?.stop()
        pruneTimer?.cancel()
        transportBridge?.stop()
    }

    /// Dock 双击 / `open` 命令重新打开 app（LSUIElement=true 时仍会触发）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            triggerPassive(reason: "reopen")
        }
        return true
    }

    /// Spotlight / Launchpad / `open .app` 等让 app 成为 frontmost 时触发。
    @objc
    private func handleAppBecameActive(_ note: Notification) {
        guard bootstrapped else { return }
        triggerPassive(reason: "becameActive")
    }

    /// 被动触发（reopen / didBecomeActive / launch）的统一入口。
    /// 多个被动 hook 共享一个去抖窗口（500ms），避免 Spotlight 同时触发 reopen + didBecomeActive
    /// 时第二次 toggle 关掉刚弹出的窗口。已显示时直接跳过，不要把刚弹的关掉。
    private func triggerPassive(reason: String) {
        guard Date() > passiveTriggerSuppressUntil else { return }
        guard !OnboardingWindowController.isVisible else { return }
        guard let presenter = statusBarController?.presenter else { return }
        guard !presenter.isShowing else {
            // 已经在显示——可能是另一个 hook 抢先弹出来了，把去抖窗口续上
            passiveTriggerSuppressUntil = Date().addingTimeInterval(0.5)
            return
        }
        passiveTriggerSuppressUntil = Date().addingTimeInterval(0.5)
        presenter.toggle()
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
