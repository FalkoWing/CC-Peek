import SwiftUI
import UIKit

// 首次启动引导(1 屏): 欢迎 + Mac 端下载提示 + 权限预告 + 开始配对/演示模式入口
//
// 设计偏离原 PRD 2 屏方案: 本地网络权限说明不单独占一屏 —
// iOS 用户对系统权限弹窗有共识, 单独说明屏价值低, 系统弹窗自然触发即可.
// 本屏底部一行小字预告"会请求本地网络授权"足够.

struct OnboardingView: View {
    let onStart: () -> Void
    let onDemoStart: () -> Void

    @State private var copyJustTapped = false

    private static let downloadURL = "ccpeek.com"

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                topChrome

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heroText
                        downloadCard
                        permissionHint
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }

                bottomActions
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topChrome: some View {
        HStack {
            Text("CC PEEK · 欢迎")
                .font(Theme.mono(11, weight: .regular))
                .tracking(1.32)
                .foregroundStyle(Theme.fgFaint)
            Spacer()
            Text("v\(versionString)")
                .font(Theme.mono(10.5, weight: .regular))
                .tracking(1.05)
                .foregroundStyle(Theme.fgFaint)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .overlay(
            Rectangle().fill(Theme.lineSoft).frame(height: 1),
            alignment: .bottom
        )
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("把 Claude Code\n装进你的口袋")
                .font(Theme.ui(28, weight: .bold))
                .foregroundStyle(Theme.fg)
                .lineSpacing(4)

            Text("在 iPhone 上实时查看 Mac 端 Claude Code 的运行状态,一键切回对应终端窗口。")
                .font(Theme.ui(14, weight: .regular))
                .foregroundStyle(Theme.fgMuted)
                .lineSpacing(3)
        }
        .padding(.top, 8)
    }

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fgMuted)
                Text("Mac 端下载")
                    .font(Theme.mono(11, weight: .semibold))
                    .tracking(0.66)
                    .foregroundStyle(Theme.fgMuted)
            }

            HStack(spacing: 12) {
                Text(Self.downloadURL)
                    .font(Theme.mono(16, weight: .semibold))
                    .foregroundStyle(Theme.fg)

                Spacer(minLength: 0)

                Button(action: copyDownloadURL) {
                    HStack(spacing: 4) {
                        Image(systemName: copyJustTapped ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(copyJustTapped ? "已复制" : "复制")
                            .font(Theme.mono(11, weight: .semibold))
                            .tracking(0.42)
                    }
                    .foregroundStyle(copyJustTapped ? Theme.statusActive : Theme.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.oklch(0.26, 0.012, 248, alpha: 0.7))
                    )
                    .overlay(
                        Capsule().strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Text("先在 Mac 上访问该地址下载安装,启动后再回到这里开始配对。")
                .font(Theme.ui(12, weight: .regular))
                .foregroundStyle(Theme.fgDim)
                .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.oklch(0.20, 0.011, 250, alpha: 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
        )
    }

    private var permissionHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.fgFaint)
                .padding(.top, 1)
            Text("开始配对后系统会请求本地网络权限,需要允许才能在同一 Wi-Fi 下发现 Mac。")
                .font(Theme.ui(12, weight: .regular))
                .foregroundStyle(Theme.fgDim)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Button(action: onStart) {
                Text("开始配对")
                    .font(Theme.ui(15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.oklch(0.62, 0.16, 240), Color.oklch(0.52, 0.18, 250)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.oklch(0.40, 0.18, 250, alpha: 0.45), radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            // A5 演示模式: 走 DemoTransport 模拟一台已配对 Mac, UI 路径与真实端一致
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDemoStart()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text("演示模式")
                        .font(Theme.ui(13, weight: .semibold))
                }
                .foregroundStyle(Theme.fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.oklch(0.22, 0.011, 250, alpha: 0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private func copyDownloadURL() {
        UIPasteboard.general.string = "https://\(Self.downloadURL)"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.18)) { copyJustTapped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.25)) { copyJustTapped = false }
        }
    }
}

// MARK: - 引导完成状态(UserDefaults 直存,不抽 Storage)

enum OnboardingState {
    private static let key = "ccpeek.iosOnboardingCompleted"

    static var completed: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

#Preview {
    OnboardingView(onStart: {}, onDemoStart: {})
}
