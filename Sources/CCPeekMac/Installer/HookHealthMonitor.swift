import Foundation
import Combine

/// 周期性检查 ~/.claude/settings.json 中 cc-peek hook 是否完整.
/// 启动时 + 每 10 分钟 跑一次 HookInstaller.validate(). 异常 → @Published hasError = true,
/// 菜单栏 / Dashboard banner / Settings sidebar 同步显示红点.
///
/// 仅在用户走完 onboarding 后才报错——新机器还没装就报错是误导.
@MainActor
final class HookHealthMonitor: ObservableObject {
    static let shared = HookHealthMonitor()

    @Published private(set) var hasError: Bool = false

    private var timer: DispatchSourceTimer?
    private static let interval: DispatchTimeInterval = .seconds(600)  // 10 min

    private init() {}

    func start() {
        checkNow()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        t.setEventHandler { [weak self] in
            self?.checkNow()
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// 立即重检. 用户在 SettingsView 重装 hook 后调用一次, banner / 红点立刻消失.
    func checkNow() {
        // 用户没走过 onboarding 时不报错——hook 没装是预期状态.
        guard OnboardingWindowController.hasCompleted() else {
            if hasError { hasError = false }
            return
        }
        let healthy = HookInstaller.validate()
        let next = !healthy
        if hasError != next {
            hasError = next
        }
    }
}
