import AppKit

@main
@MainActor
struct CCPeekApp {
    static func main() {
        let app = NSApplication.shared
        // 菜单栏应用: 避免开发期 Dock 闪默认图标, 必须在 run() 前切 accessory.
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
