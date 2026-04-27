import SwiftUI
import UIKit
import CCPeekCore

// 设置页 —— 设计稿 cc-peek-ui/screens.jsx 的 Settings
// iOS-3c: 已配对 Mac 列表 + 系统权限 + 显示 (常亮 toggle) + 关于 + 解除配对

struct SettingsView: View {
    @ObservedObject var client: PeekClient
    @ObservedObject var keepAwake: KeepAwakeManager
    let onClose: () -> Void

    @State private var confirmUnpair = false

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                topChrome
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        pairedSection
                        permissionsSection
                        displaySection
                        aboutSection
                        unpairButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("解除与该 Mac 的配对?",
                            isPresented: $confirmUnpair,
                            titleVisibility: .visible) {
            Button("解除配对", role: .destructive) {
                client.unpair()
                onClose()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从设备列表移除，需要重新搜索配对")
        }
    }

    // MARK: 顶部 chrome (左 back + 中央标题 + 右占位)

    private var topChrome: some View {
        ZStack {
            HStack {
                ChromeIconButton(systemImage: "chevron.left", action: onClose)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            Text("设置")
                .font(Theme.mono(11, weight: .regular))
                .tracking(1.32)
                .foregroundStyle(Theme.fgFaint)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: 已配对的 MAC

    private var pairedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("已配对的 MAC")
            SurfaceCard {
                DeviceRow(
                    name: client.pairedHostName ?? "—",
                    subtitle: pairedSubtitle,
                    statusBadge: .current
                )
            }
        }
    }

    private var pairedSubtitle: String {
        switch client.status {
        case .connected:           return "刚刚 · Wi-Fi"
        case .connecting:          return "正在连接…"
        case .browsing, .awaitingSelection:
            return "搜索中…"
        case .disconnected:        return "已断开"
        case .idle:                return "未启动"
        }
    }

    // MARK: 系统权限

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("系统权限")
            SurfaceCard {
                SettingsRow(
                    leadingSystemImage: "wifi",
                    title: "本地网络",
                    subtitle: "已授权"
                ) {
                    grantedPill
                }
                DottedDivider()
                SettingsRow(
                    leadingSystemImage: "dot.radiowaves.left.and.right",
                    title: "蓝牙",
                    subtitle: "已授权",
                    divider: false
                ) {
                    grantedPill
                }
            }
        }
    }

    private var grantedPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.statusActive)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.statusActiveGlow, radius: 2)
            Text("已授权")
                .font(Theme.mono(10.5, weight: .medium))
                .tracking(0.42)
        }
        .foregroundStyle(Theme.statusActive)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.oklch(0.30, 0.06, 150, alpha: 0.3)))
        .overlay(Capsule().strokeBorder(Color.oklch(0.45, 0.10, 150, alpha: 0.4), lineWidth: 1))
    }

    // MARK: 显示

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("显示")
            SurfaceCard {
                SettingsRow(
                    leadingSystemImage: "sun.max",
                    title: "保持屏幕常亮",
                    subtitle: "app 在前台时阻止熄屏",
                    divider: false
                ) {
                    IOSToggle(isOn: $keepAwake.enabled)
                }
            }
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("关于")
            SurfaceCard {
                SettingsRow(title: "版本") {
                    Text(versionString)
                        .font(Theme.mono(12, weight: .regular))
                        .foregroundStyle(Theme.fgDim)
                }
                DottedDivider()
                SettingsRow(title: "Service") {
                    Text(TransportServiceType.mvp)
                        .font(Theme.mono(12, weight: .regular))
                        .foregroundStyle(Theme.fgDim)
                }
                DottedDivider()
                SettingsRow(title: "本机", divider: false) {
                    Text(UIDevice.current.name)
                        .font(Theme.mono(12, weight: .regular))
                        .foregroundStyle(Theme.fgDim)
                        .lineLimit(1)
                }
            }
        }
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "v\(v)"
    }

    // MARK: 解除配对 (设计稿 MacDetail 里的 danger 按钮)

    private var unpairButton: some View {
        VStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                confirmUnpair = true
            } label: {
                Text("解除配对")
                    .font(Theme.ui(13.5, weight: .semibold))
                    .foregroundStyle(Color.oklch(0.92, 0.10, 25))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.oklch(0.32, 0.14, 25, alpha: 0.55),
                                Color.oklch(0.24, 0.10, 25, alpha: 0.55)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.oklch(0.55, 0.18, 25, alpha: 0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            Text("将从设备列表移除，需要重新搜索配对")
                .font(Theme.mono(11, weight: .regular))
                .foregroundStyle(Theme.fgFaint)
        }
        .padding(.top, 22)
    }
}

#Preview {
    SettingsView(
        client: PeekClient(),
        keepAwake: KeepAwakeManager(),
        onClose: {}
    )
}
