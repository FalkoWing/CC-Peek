import AppKit
import SwiftUI
import CCPeekCore

/// MacUI-2.5 — Dashboard 唤起统一入口。
///
/// 同一份 DashboardView 同时承载两条路径：
/// - statusItem 可见 → NSPopover (锚到菜单栏图标)
/// - statusItem 不可见 (被 Bartender / 刘海 / 其他 app 挤掉) → 独立 NSPanel 弹在鼠标所在屏右上角
///
/// 由 StatusBarController 持有，AppDelegate 通过 statusBarController.presenter 触发。
@MainActor
final class DashboardPresenter: NSObject {
    private weak var statusItem: NSStatusItem?
    private let store: ProcessStateStore
    private let bridge: HostTransportBridge

    private let popover: NSPopover
    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    private static let firstUseHintShownKey = "ccpeek.firstUseHintShown"
    static let shortcutOpensAtMouseKey = "ccpeek.shortcutOpensAtMouse"
    private static let panelSize = NSSize(width: 400, height: 520)

    /// Panel 落点策略.
    private enum PanelOriginStrategy {
        case auto      // 贴菜单栏 icon 下方; statusItem 异常 → 鼠标所在屏右上角兜底
        case atMouse   // panel 中心对齐鼠标位置 (用户在通用设置里开了"快捷键在鼠标位置打开")
    }

    init(store: ProcessStateStore, bridge: HostTransportBridge, statusItem: NSStatusItem) {
        self.store = store
        self.bridge = bridge
        self.statusItem = statusItem

        let p = NSPopover()
        p.contentSize = Self.panelSize
        p.behavior = .transient
        p.animates = true
        p.appearance = NSAppearance(named: .darkAqua)
        self.popover = p

        super.init()

        let view = DashboardView(
            store: store,
            bridge: bridge,
            onOpenSettings: { [weak self] in
                self?.dismissAll()
                SettingsWindowController.show()
            },
            onQuit: { NSApp.terminate(nil) }
        )
        p.contentViewController = NSHostingController(rootView: view)
    }

    // MARK: - 公开入口

    /// popover 或 panel 是否处于可见状态（用于 didBecomeActive 等回调判断 noop）。
    var isShowing: Bool {
        popover.isShown || (panel?.isVisible ?? false)
    }

    /// 智能切换：popover/panel 已显示则关；否则按 statusItem 可见性选择路径。
    /// - parameter preferMouseOrigin: true → 强制走 panel 路径并把 panel 中心对齐鼠标位置
    ///   (用户开了"快捷键在鼠标位置打开"时由全局热键回调传入).
    func toggle(preferMouseOrigin: Bool = false) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let panel, panel.isVisible {
            closePanel()
            return
        }
        if preferMouseOrigin {
            showPanel(strategy: .atMouse)
        } else if isStatusItemVisible() {
            showPopover()
        } else {
            showPanel(strategy: .auto)
        }
    }

    /// 用于 reopen / 全局热键 / 全屏 app 等场景；如果 statusItem 还在就走 popover，否则 panel。
    /// 与 toggle 行为一致——这里保留独立方法是为了语义清晰。
    func togglePopoverOrPanel() {
        toggle()
    }

    /// 关掉所有形态（用于 Settings 打开前）。
    func dismissAll() {
        if popover.isShown { popover.performClose(nil) }
        if panel?.isVisible == true { closePanel() }
    }

    // MARK: - statusItem 可见性

    /// 判断菜单栏图标在屏幕的菜单栏区域里"看得到"。
    /// - 系统隐藏（length=0 / isVisible=false）→ 不可见
    /// - 被刘海或其他 app 挤出菜单栏可见区 → window frame 不在任何屏幕的可视区内
    private func isStatusItemVisible() -> Bool {
        guard let item = statusItem,
              item.isVisible,
              item.length > 0,
              let button = item.button,
              let window = button.window
        else { return false }

        // 用 button window 的中心点判断在不在某屏的 frame 内（含菜单栏 strip）。
        // 比之前严格的菜单栏 strip 相交检测更宽容——某些 macOS 版本下 NSStatusBarWindow
        // 的 frame 不一定完美贴在菜单栏 y 范围里，会造成 popover 路径误判。
        let frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.contains { $0.frame.contains(center) }
    }

    // MARK: - Popover

    private func showPopover() {
        guard let button = statusItem?.button else {
            // statusItem 没 button —— 退化为 panel
            showPanel()
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Panel

    private func showPanel(strategy: PanelOriginStrategy = .auto) {
        // 每次开新 panel 前先关旧的
        closePanel()

        let isFirstTime = !UserDefaults.standard.bool(forKey: Self.firstUseHintShownKey)

        let view = DashboardView(
            store: store,
            bridge: bridge,
            showFirstUseHint: isFirstTime,
            onOpenSettings: { [weak self] in
                self?.dismissAll()
                SettingsWindowController.show()
            },
            onQuit: { NSApp.terminate(nil) },
            onDismissFirstUseHint: {
                UserDefaults.standard.set(true, forKey: Self.firstUseHintShownKey)
            }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(origin: .zero, size: Self.panelSize)

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isFloatingPanel = true
        p.level = .floating
        p.appearance = NSAppearance(named: .darkAqua)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 借 contentView layer 给 panel 上圆角（borderless 需要自己画）
        p.contentView?.wantsLayer = true
        p.contentView?.layer?.cornerRadius = 14
        p.contentView?.layer?.masksToBounds = true
        p.hidesOnDeactivate = false

        p.setFrameOrigin(panelOrigin(strategy: strategy))
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel = p

        // 一旦开始显示，无论用户操作如何，都标记为"已显示过"避免下次再来
        if isFirstTime {
            UserDefaults.standard.set(true, forKey: Self.firstUseHintShownKey)
        }

        installDismissMonitors()
    }

    private func closePanel() {
        removeDismissMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Panel 落点策略：
    /// - `.atMouse`：panel 中心对齐鼠标位置, clamp 到鼠标所在屏 visibleFrame 内
    /// - `.auto`：贴 statusItem 按钮下方 (panel 中心对齐按钮中心, 水平 clamp 到屏幕内);
    ///   statusItem 异常 (button.window 不在任何屏 / 还没 layout 完成) → 鼠标所在屏右上角兜底
    /// 顶部留 2pt 透气, 避免 panel shadow 被菜单栏底边切掉.
    private func panelOrigin(strategy: PanelOriginStrategy = .auto) -> NSPoint {
        let topMargin: CGFloat = 2
        let edgeMargin: CGFloat = 4

        if strategy == .atMouse {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                ?? NSScreen.main
                ?? NSScreen.screens.first!
            let visible = screen.visibleFrame
            var x = mouse.x - Self.panelSize.width / 2
            var y = mouse.y - Self.panelSize.height / 2
            x = max(visible.minX + edgeMargin,
                    min(x, visible.maxX - Self.panelSize.width - edgeMargin))
            y = max(visible.minY + edgeMargin,
                    min(y, visible.maxY - Self.panelSize.height - topMargin))
            return NSPoint(x: x, y: y)
        }

        if let item = statusItem,
           let button = item.button,
           let buttonWindow = button.window {
            let buttonFrame = buttonWindow.frame
            // sanity check: 首次启动时 statusItem 可能还没完成 layout, frame 是 (0,0,1,1)
            // 之类的初始值, midX 极小. 此时算出来的 x 会被 clamp 到屏幕左边缘 → 落到左上角.
            // midX 必须够大 (至少 50pt) 才认为已布局好.
            if buttonFrame.midX > 50 {
                let center = NSPoint(x: buttonFrame.midX, y: buttonFrame.midY)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                    let visible = screen.visibleFrame
                    var x = buttonFrame.midX - Self.panelSize.width / 2
                    x = max(visible.minX + edgeMargin,
                            min(x, visible.maxX - Self.panelSize.width - edgeMargin))
                    let y = visible.maxY - Self.panelSize.height - topMargin
                    return NSPoint(x: x, y: y)
                }
            }
        }

        // 兜底: 鼠标所在屏右上角
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let rightMargin: CGFloat = 12
        return NSPoint(
            x: visible.maxX - Self.panelSize.width - rightMargin,
            y: visible.maxY - Self.panelSize.height - topMargin
        )
    }

    private func installDismissMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in self?.closePanel() }
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let m = globalClickMonitor {
            NSEvent.removeMonitor(m)
            globalClickMonitor = nil
        }
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
    }
}
