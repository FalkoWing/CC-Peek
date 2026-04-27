import AppKit
import SwiftUI

/// 单例设置窗口. PRD 3.5.5 信息架构.
@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show() {
        if let existing = shared, let window = existing.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SettingsWindowController.make()
        shared = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private static func make() -> SettingsWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CC Peek 设置"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.center()
        return SettingsWindowController(window: window)
    }
}
