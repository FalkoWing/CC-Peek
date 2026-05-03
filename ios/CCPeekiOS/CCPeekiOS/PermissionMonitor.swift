import Foundation
import Combine
import Network
import SwiftUI
import UIKit

/// iOS 本地网络权限探测.
///
/// iOS 14+ 没有公开 API 直接查询本地网络授权状态. 标准做法 (Apple Forum Quinn 推荐):
/// 同 device 上起一个 NWListener 注册临时 Bonjour service, 同时起一个 NWBrowser 浏览同 service,
/// browser 真发现 listener → granted, 超时没发现 → denied.
///
/// 实测踩过的坑 (开发期 trial-and-error):
/// 1. 不能用 NWBrowser.state == .ready 判 granted —— browser 启动就 ready, 跟权限无关
/// 2. 不能用 NWListener.state == .ready 判 granted —— 那只表示 TCP 端口监听成功,
///    Bonjour service 注册是异步且更晚的事
/// 3. 不能用 .failed 判 denied —— 权限未决定时 listener/browser 也会 fail, 区分不出
///    "未定" vs "拒绝"
/// 4. 唯一可信信号: browser 通过 mDNS 真发现了 listener (双向都通才说明权限放行)
@MainActor
final class PermissionMonitor: ObservableObject {

    enum LocalNetworkStatus: Equatable {
        case undetermined
        case granted
        case denied
    }

    @Published private(set) var localNetwork: LocalNetworkStatus = .undetermined

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var timeoutTask: Task<Void, Never>?

    /// 探测专用 service type, 跟业务 _cc-peek-v1._tcp 隔离避免污染服务发现.
    /// 必须在 Info.plist NSBonjourServices 声明.
    private let probeServiceType = "_ccpeek-permcheck._tcp"
    /// 10s 给三件事时间: ① 用户看弹窗+决定 ② listener 注册 Bonjour service
    /// ③ browser 通过 mDNS 自发现 listener. 短了会在权限其实允许的情况下误判 denied.
    private let probeTimeout: Duration = .seconds(10)

    /// 启动一次本地网络授权探测. 可反复调用 (例如用户从系统设置回到 app 时).
    func probeLocalNetwork() {
        cancelProbe()
        localNetwork = .undetermined

        do {
            let listener = try NWListener(using: NWParameters.tcp)
            listener.service = NWListener.Service(name: nil, type: probeServiceType)
            listener.newConnectionHandler = { $0.cancel() }
            // listener.state 不参与判定:
            // - .ready 只表示 TCP 端口监听成功, 跟 Bonjour 注册成败无关
            // - .failed 在权限未决定时也会触发, 区分不出"未定"vs"拒绝"
            // 真正的 granted 信号是 browser 实际发现了这个 listener.
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            // listener 创建失败 (极端情况, 与权限无关) 仍走 timeout 路径
        }

        let browser = NWBrowser(
            for: .bonjour(type: probeServiceType, domain: nil),
            using: NWParameters.tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // Task 上重新声明 [weak self] 让 Swift 6 看清并发捕获语义,
            // 避免"reference to captured var 'self' in concurrently-executing code"警告.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !results.isEmpty { self.markGranted() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: self?.probeTimeout ?? .seconds(5))
            await MainActor.run {
                guard let self else { return }
                if self.localNetwork == .undetermined {
                    self.markDenied()
                }
            }
        }
    }

    /// 跳到本 app 的系统设置页 (用户可在此调权限开关).
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 业务层已经通过 Bonjour/MPC 发现或连接到 Mac.
    /// 这比自建 listener/browser 探测更强, 可用来消除偶发的 denied 误判.
    func noteLocalNetworkActivity() {
        markGranted()
    }

    private func markGranted() {
        guard localNetwork != .granted else { return }
        localNetwork = .granted
        cancelProbe()
    }

    private func markDenied() {
        guard localNetwork != .denied else { return }
        localNetwork = .denied
        cancelProbe()
    }

    private func cancelProbe() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

// MARK: - PermissionBanner

/// 顶部红条提示: 权限被拒时全局挂 ContentView 顶层 (PRD 3.6.6 / iOS 异常态).
struct PermissionBanner: View {
    let title: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.oklch(0.85, 0.12, 25))

            Text(title)
                .font(Theme.ui(13, weight: .medium))
                .foregroundStyle(Theme.fg)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(action: onOpenSettings) {
                HStack(spacing: 4) {
                    Text("去设置")
                        .font(Theme.ui(12, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.oklch(0.92, 0.06, 25))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.oklch(0.30, 0.10, 25, alpha: 0.45))
                )
                .overlay(
                    Capsule().strokeBorder(Color.oklch(0.55, 0.14, 25, alpha: 0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.oklch(0.28, 0.08, 25, alpha: 0.32))
        .overlay(
            Rectangle().fill(Color.oklch(0.55, 0.14, 25, alpha: 0.45)).frame(height: 0.5),
            alignment: .bottom
        )
    }
}
