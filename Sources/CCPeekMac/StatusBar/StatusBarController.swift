import AppKit
import Combine
import SwiftUI
import CCPeekCore

@MainActor
final class StatusBarController: NSObject {
    let statusItem: NSStatusItem
    let presenter: DashboardPresenter
    private let store: ProcessStateStore
    private let bridge: HostTransportBridge
    private var cancellables = Set<AnyCancellable>()
    private var appAppearanceObservation: NSKeyValueObservation?
    private var buttonAppearanceObservation: NSKeyValueObservation?
    private var lastIconKey: IconKey?

    private struct IconKey: Equatable {
        let waitingCount: Int
        let hasConnectedPhone: Bool
        let hasHookError: Bool
        let isDark: Bool
    }

    init(store: ProcessStateStore, bridge: HostTransportBridge) {
        self.store = store
        self.bridge = bridge
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.presenter = DashboardPresenter(store: store, bridge: bridge, statusItem: statusItem)
        super.init()

        setupStatusItem()
        bindIconUpdates()
        refreshIconAfterStatusItemSettles()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = StatusIconBuilder.build(
                waitingCount: 0,
                appearance: button.effectiveAppearance
            )
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
        }
    }

    /// 监听 store.processes + bridge.connectedPeerCount + HookHealthMonitor.hasError,
    /// 节流 1s 重绘 (PRD 3.5.2 重绘节流要求).
    /// 同时监听 App / 菜单栏按钮 appearance，深浅色切换时立即重绘。
    private func bindIconUpdates() {
        Publishers.CombineLatest3(
            store.$processes,
            bridge.$connectedPeerCount,
            HookHealthMonitor.shared.$hasError
        )
        .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
        .sink { [weak self] processes, peerCount, hookError in
            self?.refreshIcon(processes: processes, peerCount: peerCount, hookError: hookError)
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
        refreshIcon(
            processes: store.processes,
            peerCount: bridge.connectedPeerCount,
            hookError: HookHealthMonitor.shared.hasError
        )
    }

    private func refreshIconAfterStatusItemSettles() {
        Task { @MainActor in
            await Task.yield()
            refreshIcon()
        }
    }

    private func refreshIcon(processes: [ClaudeProcess], peerCount: Int, hookError: Bool) {
        let count = processes.filter {
            $0.state == .waitingInput || $0.state == .waitingPermission
        }.count
        let buttonAppearance = statusItem.button?.effectiveAppearance
        let isDark = (buttonAppearance ?? NSApp.effectiveAppearance)
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key = IconKey(
            waitingCount: count,
            hasConnectedPhone: peerCount > 0,
            hasHookError: hookError,
            isDark: isDark
        )
        guard key != lastIconKey else { return }
        lastIconKey = key

        statusItem.button?.image = StatusIconBuilder.build(
            waitingCount: count,
            hasConnectedPhone: peerCount > 0,
            hasHookError: hookError,
            appearance: buttonAppearance
        )
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        presenter.toggle()
    }
}
