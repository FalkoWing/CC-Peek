import SwiftUI
import CCPeekCore

/// 顶层路由: 监听演示模式开关, 切换时通过 .id() 让子树整树重建,
/// @StateObject<PeekClient> 跟着重建从而切到对应 transport.
struct ContentView: View {
    @AppStorage("ccpeek.iosDemoMode") private var isDemoMode = false

    var body: some View {
        ContentRoot(isDemoMode: isDemoMode)
            .id(isDemoMode)
    }
}

private struct ContentRoot: View {
    let isDemoMode: Bool
    @StateObject private var client: PeekClient
    @StateObject private var keepAwake = KeepAwakeManager()
    @StateObject private var permissionMonitor = PermissionMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showDeviceSwitcher = false
    @State private var onboardingDone = OnboardingState.completed

    init(isDemoMode: Bool) {
        self.isDemoMode = isDemoMode
        _client = StateObject(wrappedValue: PeekClient(mode: isDemoMode ? .demo : .real))
    }

    var body: some View {
        ZStack {
            Group {
                if !onboardingDone {
                    OnboardingView(
                        onStart: completeOnboarding,
                        onDemoStart: enterDemoFromOnboarding
                    )
                    .transition(.opacity)
                } else if client.isPaired {
                    // 已配对: 沉浸式仪表盘，自带 TopBar/BottomBar (设计稿 dashboard.jsx)
                    DashboardScreen(
                        processes: client.processes,
                        macName: client.pairedHostName ?? "Mac",
                        isConnected: isConnected,
                        isDemo: client.isDemo,
                        onSettingsTap: { showSettings = true },
                        onMacTap: { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showDeviceSwitcher = true } },
                        onCardTap: { client.switchTo($0) },
                        onRetryConnect: { client.restart() },
                        onRefresh: { client.requestSnapshot() },
                        staleSince: staleSince,
                        switchErrors: client.switchErrors
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    PairView(client: client)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: client.isPaired)
            .animation(.easeInOut(duration: 0.4), value: onboardingDone)

            if showDeviceSwitcher {
                DeviceSwitcherView(client: client) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showDeviceSwitcher = false
                    }
                }
                .zIndex(1)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // 演示模式跳过权限 banner: 演示用户没真在用本地网络发现, banner 没意义.
            // 已连接时说明本地网络实际可用, 不显示探测误判产生的"无法发现 Mac".
            if shouldShowPermissionBanner {
                PermissionBanner(
                    title: "本地网络权限未授权,无法发现 Mac",
                    onOpenSettings: { permissionMonitor.openAppSettings() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: permissionMonitor.localNetwork)
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client, keepAwake: keepAwake, permissionMonitor: permissionMonitor) {
                showSettings = false
            }
        }
        .onAppear {
            if onboardingDone { startActiveSession() }
        }
        .onChange(of: scenePhase) { _, phase in
            keepAwake.updateForScenePhase(phase)
            // 用户从系统设置回到 app, 重新探测一次 (可能刚改完授权).
            // 演示模式下不探测, 避免给用户弹本地网络权限弹窗.
            if phase == .active, shouldProbeLocalNetwork {
                permissionMonitor.probeLocalNetwork()
            }
        }
        .onChange(of: client.status) { _, status in
            if case .connected = status {
                permissionMonitor.noteLocalNetworkActivity()
            }
        }
        .onChange(of: client.discoveredHosts.count) { _, count in
            if count > 0 {
                permissionMonitor.noteLocalNetworkActivity()
            }
        }
    }

    private func completeOnboarding() {
        OnboardingState.markCompleted()
        onboardingDone = true
        startActiveSession()
    }

    /// 引导页 → 演示模式: 标 onboarding 完成 + 写 demoMode flag.
    /// AppStorage 变化触发顶层 ContentView .id 重建, 自动用 PeekClient(.demo) 替换实例.
    private func enterDemoFromOnboarding() {
        OnboardingState.markCompleted()
        UserDefaults.standard.set(true, forKey: "ccpeek.iosDemoMode")
    }

    /// 引导完成或冷启动已完成引导时调用: 拉起 transport + 触发权限探测.
    /// 引导未完成时不调用,避免权限弹窗夹在引导页之前破坏首次体验.
    /// 演示模式下不触发权限探测 (DemoTransport 不需要本地网络).
    private func startActiveSession() {
        client.start()
        if shouldProbeLocalNetwork {
            permissionMonitor.probeLocalNetwork()
        }
    }

    private var isConnected: Bool {
        if case .connected = client.status { return true }
        return false
    }

    private var shouldProbeLocalNetwork: Bool {
        onboardingDone && !isDemoMode && !isConnected && client.discoveredHosts.isEmpty
    }

    private var shouldShowPermissionBanner: Bool {
        !isDemoMode && !isConnected && permissionMonitor.localNetwork == .denied
    }

    /// PRD 3.3.5: 断开但仍在 5 分钟 stale window 内 → 返回 disconnect 时间 (UI 据此显示 stale banner).
    /// connected / 超出 window / 从未连过 时返回 nil.
    private var staleSince: Date? {
        guard !isConnected, let t = client.lastDisconnectedAt else { return nil }
        return Date().timeIntervalSince(t) <= PeekClient.staleWindow ? t : nil
    }
}

#Preview {
    ContentView()
}
