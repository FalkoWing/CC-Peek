import Foundation
import Combine
import SwiftUI
import UIKit

// 屏幕常亮管理器: 用户偏好 (UserDefaults) + scenePhase 联动
//
// 规则:
// - 偏好默认 true (首次启动)
// - 仅当 scenePhase == .active 且偏好为 true 时, isIdleTimerDisabled=true
// - 切到后台 / 偏好关闭时, isIdleTimerDisabled=false (释放锁, 走系统全局设置)
@MainActor
final class KeepAwakeManager: ObservableObject {

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.key)
            applyIfActive()
        }
    }

    private static let key = "ccpeek.keepAwake"
    private var currentPhase: ScenePhase = .inactive

    init() {
        // 首次启动: 默认 true
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            UserDefaults.standard.set(true, forKey: Self.key)
        }
        self.enabled = UserDefaults.standard.bool(forKey: Self.key)
    }

    func updateForScenePhase(_ phase: ScenePhase) {
        currentPhase = phase
        if phase == .active {
            applyIfActive()
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func applyIfActive() {
        guard currentPhase == .active else { return }
        UIApplication.shared.isIdleTimerDisabled = enabled
    }
}
