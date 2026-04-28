import AppKit
import Combine
import SwiftUI
import CCPeekCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: ProcessStateStore
    private let bridge: HostTransportBridge
    private var cancellables = Set<AnyCancellable>()
    private var appAppearanceObservation: NSKeyValueObservation?
    private var buttonAppearanceObservation: NSKeyValueObservation?

    init(store: ProcessStateStore, bridge: HostTransportBridge) {
        self.store = store
        self.bridge = bridge
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        setupStatusItem()
        setupPopover()
        bindIconUpdates()
        refreshIconAfterStatusItemSettles()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = StatusIconBuilder.build(
                waitingCount: 0,
                appearance: button.effectiveAppearance
            )
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    /// 监听 store.processes + bridge.connectedPeerCount, 节流 1s 重绘 (PRD 3.5.2 重绘节流要求).
    /// 同时监听 App / 菜单栏按钮 appearance，深浅色切换时立即重绘。
    private func bindIconUpdates() {
        Publishers.CombineLatest(store.$processes, bridge.$connectedPeerCount)
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] processes, peerCount in
                self?.refreshIcon(processes: processes, peerCount: peerCount)
            }
            .store(in: &cancellables)

        appAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshIcon()
            }
        }

        buttonAppearanceObservation = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshIcon()
            }
        }

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        refreshIcon(processes: store.processes, peerCount: bridge.connectedPeerCount)
    }

    private func refreshIconAfterStatusItemSettles() {
        Task { @MainActor in
            await Task.yield()
            refreshIcon()
        }
    }

    private func refreshIcon(processes: [ClaudeProcess], peerCount: Int) {
        let count = processes.filter {
            $0.state == .waitingInput || $0.state == .waitingPermission
        }.count
        let buttonAppearance = statusItem.button?.effectiveAppearance
        statusItem.button?.image = StatusIconBuilder.build(
            waitingCount: count,
            hasConnectedPhone: peerCount > 0,
            hasHookError: false,  // MVP: 暂不接入 Hook 异常实时检测
            appearance: buttonAppearance
        )
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 400, height: 520)
        popover.behavior = .transient
        popover.animates = true
        // 强制深色外观，避免系统浅色 mode 下 popover vibrancy 透出浅色调
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(store: store, bridge: bridge)
        )
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
