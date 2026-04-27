import AppKit
import Combine
import SwiftUI
import CCPeekCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: ProcessStateStore
    private var cancellables = Set<AnyCancellable>()

    init(store: ProcessStateStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        setupStatusItem()
        setupPopover()
        bindIconUpdates()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = StatusIconBuilder.build(waitingCount: 0)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    /// 监听 store.processes, 节流 1s 重绘 (PRD 3.5.2 重绘节流要求).
    private func bindIconUpdates() {
        store.$processes
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] processes in
                self?.refreshIcon(for: processes)
            }
            .store(in: &cancellables)
    }

    private func refreshIcon(for processes: [ClaudeProcess]) {
        let count = processes.filter {
            $0.state == .waitingInput || $0.state == .waitingPermission
        }.count
        statusItem.button?.image = StatusIconBuilder.build(waitingCount: count)
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(store: store)
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
