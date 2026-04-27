import SwiftUI
import CCPeekCore

struct ContentView: View {
    @StateObject private var client = PeekClient()
    @StateObject private var keepAwake = KeepAwakeManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showDeviceSwitcher = false

    var body: some View {
        ZStack {
            Group {
                if client.isPaired {
                    // 已配对: 沉浸式仪表盘，自带 TopBar/BottomBar (设计稿 dashboard.jsx)
                    DashboardScreen(
                        processes: client.processes,
                        macName: client.pairedHostName ?? "Mac",
                        isConnected: isConnected,
                        onSettingsTap: { showSettings = true },
                        onMacTap: { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showDeviceSwitcher = true } },
                        onCardTap: { client.switchTo($0) },
                        onRetryConnect: { client.restart() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    PairView(client: client)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: client.isPaired)

            if showDeviceSwitcher {
                DeviceSwitcherView(client: client) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showDeviceSwitcher = false
                    }
                }
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client, keepAwake: keepAwake) {
                showSettings = false
            }
        }
        .onAppear { client.start() }
        .onChange(of: scenePhase) { _, phase in
            keepAwake.updateForScenePhase(phase)
        }
    }

    private var isConnected: Bool {
        if case .connected = client.status { return true }
        return false
    }
}

#Preview {
    ContentView()
}
