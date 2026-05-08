import SwiftUI
import CCPeekCore

// 首次配对流程 —— 设计稿 cc-peek-ui/screens.jsx 的 PairScanning / PairFound / PairEmpty
// PairSuccess 跳过 (isPaired=true 后 ContentView 直接切到 DashboardScreen)
//
// 三态切换:
// - discoveredHosts 非空                       → PairFoundView
// - discoveredHosts 空 + 8s 内                 → PairScanningView (雷达扫描)
// - discoveredHosts 空 + 8s 后                 → PairEmptyView (检查清单)

struct PairView: View {
    @ObservedObject var client: PeekClient

    @State private var showEmpty = false
    @State private var emptyTimerTask: Task<Void, Never>?

    private static let emptyTimeoutSeconds: UInt64 = 8

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                pairChrome
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                demoFooter
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startEmptyTimer() }
        .onDisappear { emptyTimerTask?.cancel() }
        .onChange(of: client.discoveredHosts.count) { _, count in
            if count > 0 { showEmpty = false }
        }
    }

    // MARK: 演示模式 footer (Mac 端没启动 / 模拟器 / 体验试用 时给一条出路)
    // 三态(scanning / found / empty)统一展示, 样式低调不抢主流程焦点.

    private var demoFooter: some View {
        Button(action: enterDemoMode) {
            HStack(spacing: 6) {
                Image(systemName: "play.circle")
                    .font(.system(size: 12, weight: .medium))
                Text("先体验演示模式")
                    .font(Theme.ui(12.5, weight: .medium))
            }
            .foregroundStyle(Theme.fgMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.oklch(0.20, 0.011, 250, alpha: 0.6))
            )
            .overlay(
                Capsule().strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 18)
        .padding(.top, 4)
    }

    private func enterDemoMode() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UserDefaults.standard.set(true, forKey: "ccpeek.iosDemoMode")
    }

    // MARK: 顶部 chrome (设计稿 PairChrome)

    private var pairChrome: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CC PEEK · 首次配对")
                    .font(Theme.mono(11, weight: .regular))
                    .tracking(1.32)
                    .foregroundStyle(Theme.fgFaint)
                Spacer()
                Text("v\(versionString)")
                    .font(Theme.mono(10.5, weight: .regular))
                    .tracking(1.05)
                    .foregroundStyle(Theme.fgFaint)
            }
            if let subtitle = chromeSubtitle {
                Text(subtitle)
                    .font(Theme.mono(11.5, weight: .regular))
                    .foregroundStyle(Theme.fgDim)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .overlay(
            Rectangle().fill(Theme.lineSoft).frame(height: 1),
            alignment: .bottom
        )
    }

    private var chromeSubtitle: String? {
        if !client.discoveredHosts.isEmpty {
            if case .connecting(let peer) = client.status {
                return String(localized: "正在等待 \(peer) 确认…")
            }
            return String(localized: "已发现下列设备")
        }
        return nil
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    // MARK: content 三态

    @ViewBuilder
    private var content: some View {
        if !client.discoveredHosts.isEmpty {
            PairFoundView(client: client)
        } else if showEmpty {
            PairEmptyView(onRetry: retry)
        } else {
            PairScanningView()
        }
    }

    private func startEmptyTimer() {
        emptyTimerTask?.cancel()
        showEmpty = false
        emptyTimerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.emptyTimeoutSeconds * 1_000_000_000)
            if !Task.isCancelled, client.discoveredHosts.isEmpty {
                showEmpty = true
            }
        }
    }

    private func retry() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        client.restart()
        startEmptyTimer()
    }
}

// MARK: - Scanning (雷达扫描)

private struct PairScanningView: View {
    @State private var phase: Double = 0  // 0..1 用于循环 (3 个圆错开)

    var body: some View {
        VStack(spacing: 28) {
            radar
            VStack(spacing: 8) {
                Text("正在搜索附近的 Mac…")
                    .font(Theme.ui(18, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text("请确保 Mac 端 CC Peek 已启动")
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.fgDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var radar: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RadarRing(delay: Double(i) * 0.8)
            }
            // 中央 icon 容器
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.oklch(0.30, 0.06, 240), Color.oklch(0.22, 0.04, 240)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.oklch(0.55, 0.10, 240, alpha: 0.6), lineWidth: 1)
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.oklch(0.55, 0.14, 240, alpha: 0.4), radius: 14)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Color.oklch(0.92, 0.04, 240))
            }
        }
        .frame(width: 160, height: 160)
    }
}

// 一圈雷达脉冲: scale 0.4→1.4, opacity 0→1→0, 2.4s 周期 ease-in-out, 错开 delay
private struct RadarRing: View {
    let delay: Double

    @State private var animate = false

    var body: some View {
        Circle()
            .strokeBorder(Color.oklch(0.45, 0.10, 240, alpha: 0.4), lineWidth: 1)
            .scaleEffect(animate ? 1.4 : 0.4)
            .opacity(animate ? 0 : 1)
            .animation(
                .easeInOut(duration: 2.4)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: animate
            )
            .onAppear { animate = true }
    }
}

// MARK: - Found (设备列表)

private struct PairFoundView: View {
    @ObservedObject var client: PeekClient

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(client.discoveredHosts, id: \.id) { host in
                    PairDeviceRow(
                        name: host.displayName,
                        isAwaiting: isAwaiting(host: host),
                        isCurrent: isCurrentlyConnecting(host: host),
                        onTap: { selectDevice(host) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
    }

    private func isAwaiting(host: TransportPeer) -> Bool {
        if case .connecting(let name) = client.status, name == host.displayName {
            return true
        }
        return false
    }

    private func isCurrentlyConnecting(host: TransportPeer) -> Bool {
        isAwaiting(host: host)
    }

    private func selectDevice(_ host: TransportPeer) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        client.selectAndPair(host)
    }
}

private struct PairDeviceRow: View {
    let name: String
    let isAwaiting: Bool
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.oklch(0.20, 0.010, 250))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.lineSoft, lineWidth: 1)
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "macbook")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(isCurrent ? Theme.accent : Theme.fgMuted)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Theme.ui(14.5, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Text("局域网内可达")
                        .font(Theme.mono(11.5, weight: .regular))
                        .foregroundStyle(Theme.fgDim)
                }
                Spacer(minLength: 0)

                if isAwaiting {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(0.85)
                } else {
                    SignalDots(level: 3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.oklch(0.21, 0.011, 250), Color.oklch(0.18, 0.010, 250)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isCurrent ? Theme.accent : Theme.cardHighlightSoft,
                        lineWidth: isCurrent ? 1.5 : 1
                    )
            )
            .shadow(
                color: isCurrent ? Color.oklch(0.55, 0.14, 240, alpha: 0.25) : Theme.cardOuterShadow3,
                radius: isCurrent ? 11 : 6, x: 0, y: 4
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAwaiting)
    }
}

// 信号格 (3 条, level=1/2/3)
private struct SignalDots: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                let on = i <= level
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(on ? Theme.statusActive : Color.oklch(0.30, 0.012, 250))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
                    .shadow(color: on ? Theme.statusActiveGlow : .clear, radius: 2)
            }
        }
        .frame(height: 14)
    }
}

// MARK: - Empty (检查清单)

private struct PairEmptyView: View {
    let onRetry: () -> Void

    private let checkItems: [String] = [
        String(localized: "Mac 端 CC Peek 已启动"),
        String(localized: "两台设备均已开启 Wi-Fi"),
        String(localized: "两台设备在同一 Wi-Fi 下"),
        String(localized: "iPhone 已授予本地网络权限")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.oklch(0.22, 0.011, 250), Color.oklch(0.18, 0.010, 250)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
                            )
                            .frame(width: 64, height: 64)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(Theme.fgFaint)
                    }
                    Text("未发现 Mac 设备")
                        .font(Theme.ui(17, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                }
                .padding(.top, 14)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("请检查")
                            .font(Theme.mono(10.5, weight: .regular))
                            .tracking(1.26)
                            .foregroundStyle(Theme.fgFaint)
                        ForEach(Array(checkItems.enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.oklch(0.25, 0.012, 250))
                                        .overlay(
                                            Circle().strokeBorder(Theme.lineSoft, lineWidth: 1)
                                        )
                                        .frame(width: 14, height: 14)
                                    Text("\(idx + 1)")
                                        .font(Theme.mono(9, weight: .regular))
                                        .foregroundStyle(Theme.fgDim)
                                }
                                Text(item)
                                    .font(Theme.ui(13, weight: .regular))
                                    .foregroundStyle(Theme.fgMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                        Text("重新搜索")
                            .font(Theme.ui(13.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.fg)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.oklch(0.24, 0.012, 248), Color.oklch(0.20, 0.010, 250)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                            .strokeBorder(Theme.cardHighlightSoft, lineWidth: 0.5)
                    )
                    .shadow(color: Theme.cardOuterShadow1, radius: 1, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
    }
}

#Preview("Scanning") {
    PairView(client: PeekClient())
}
