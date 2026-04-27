import AppKit
import SwiftUI

@MainActor
final class DiagnosticLogWindowController: NSWindowController {
    private static var shared: DiagnosticLogWindowController?

    static func show() {
        if let existing = shared, let window = existing.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DiagnosticLogWindowController.make()
        shared = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private static func make() -> DiagnosticLogWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CC Peek 诊断日志"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 360)
        window.contentViewController = NSHostingController(rootView: DiagnosticLogView())
        window.center()
        return DiagnosticLogWindowController(window: window)
    }
}
