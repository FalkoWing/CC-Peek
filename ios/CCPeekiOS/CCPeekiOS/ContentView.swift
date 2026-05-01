import SwiftUI
import CCPeekCore

struct ContentView: View {
    @StateObject private var client = PeekClient()
    @StateObject private var keepAwake = KeepAwakeManager()
    @StateObject private var permissionMonitor = PermissionMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showDeviceSwitcher = false
    @State private var onboardingDone = OnboardingState.completed

    var body: some View {
        ZStack {
            Group {
                if !onboardingDone {
                    OnboardingView(onStart: completeOnboarding)
                        .transition(.opacity)
                } else if client.isPaired {
                    // 已配对: 沉浸式仪表盘，自带 TopBar/BottomBar (设计稿 dashboard.jsx)
                    DashboardScreen(
                        processes: client.processes,
                        macName: client.pairedHostName ?? "Mac",
                        isConnected: isConnected,
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
            if permissionMonitor.localNetwork == .denied {
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
            // 用户从系统设置回到 app, 重新探测一次 (可能刚改完授权)
            if phase == .active, onboardingDone {
                permissionMonitor.probeLocalNetwork()
            }
        }
    }

    private func completeOnboarding() {
        OnboardingState.markCompleted()
        onboardingDone = true
        startActiveSession()
    }

    /// 引导完成或冷启动已完成引导时调用: 拉起 transport + 触发权限探测.
    /// 引导未完成时不调用,避免权限弹窗夹在引导页之前破坏首次体验.
    private func startActiveSession() {
        client.start()
        permissionMonitor.probeLocalNetwork()
    }

    private var isConnected: Bool {
        if case .connected = client.status { return true }
        return false
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
