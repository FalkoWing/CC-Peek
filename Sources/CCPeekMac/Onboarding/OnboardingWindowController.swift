import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    private static var shared: OnboardingWindowController?

    static let completedKey = "ccpeek.onboardingCompleted"

    static func hasCompleted() -> Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static var isVisible: Bool {
        shared?.window?.isVisible ?? false
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    static func show(force: Bool = false) {
        if !force, hasCompleted() { return }

        // force=true (用户从设置点"重看引导") 必须重建, 否则旧 SwiftUI State
        // 卡在 .done 上, 用户看到的就是"配置完成"页.
        if force {
            shared?.close()
            shared = nil
        }

        if let existing = shared, let window = existing.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = OnboardingWindowController.make()
        shared = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private static func make() -> OnboardingWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CC Peek 引导"
        window.isReleasedWhenClosed = false
        let controller = OnboardingWindowController(window: window)
        let hostingView = OnboardingView(onFinish: { [weak controller] in
            OnboardingWindowController.markCompleted()
            controller?.close()
        })
        window.contentViewController = NSHostingController(rootView: hostingView)
        // center 必须在 setContentViewController 之后调: hosting view 的 intrinsic size
        // 会触发 window resize, 在 center 之前设会让 center 计算的 origin 失效.
        window.center()
        return controller
    }
}
