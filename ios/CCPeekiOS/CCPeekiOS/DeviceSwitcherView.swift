import SwiftUI
import CCPeekCore

// 设备切换浮层 —— 设计稿 cc-peek-ui/screens.jsx 的 DeviceSwitcher
// iOS-3e: 单 Mac 简化版 —— 当前 Mac + "正在搜索其他设备…"占位
// 多 Mac 真切换留给 iOS-4c

struct DeviceSwitcherView: View {
    @ObservedObject var client: PeekClient
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // 半透明蒙版 (点击关闭)
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .transition(.opacity)

            // 浮层 sheet
            sheet
                .padding(.horizontal, 24)
                .padding(.top, 60)            // 让出 TopBar 区域
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(localized: "正在连接"))
            DeviceRow(
                name: client.pairedHostName ?? "—",
                subtitle: String(localized: "本地网络 · Wi-Fi"),
                statusBadge: .current
            )
            DottedDivider()
            // iOS-3e 占位: 真多 Mac 切换留给 iOS-4c
            HStack(spacing: 12) {
                ScanningDot()
                Text("正在搜索其他设备…")
                    .font(Theme.ui(13.5, weight: .regular))
                    .foregroundStyle(Theme.fgMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(
            LinearGradient(
                colors: [Color.oklch(0.22, 0.011, 250), Color.oklch(0.18, 0.010, 250)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.lineSoft, lineWidth: 1)
        )
        .shadow(color: Color.oklch(0.04, 0.005, 250, alpha: 0.6), radius: 20, x: 0, y: 18)
        .shadow(color: Color.oklch(0.04, 0.005, 250, alpha: 0.5), radius: 6, x: 0, y: 4)
    }

    // SectionLabel 在 SharedDesign 里是带左右 padding 的; 浮层里我们要紧贴 16, 所以重写一个简化版
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10.5, weight: .regular))
            .tracking(1.26)
            .foregroundStyle(Theme.fgFaint)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

// "扫描中"小蓝点 (设计稿 .dot.scanning)
private struct ScanningDot: View {
    @State private var phase = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .shadow(color: Color.oklch(0.72, 0.14, 240, alpha: 0.4), radius: 3)
            .opacity(phase ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}
