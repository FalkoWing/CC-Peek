import SwiftUI
import AppKit
import CCPeekCore

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case hookConfig
        case iphone
        case done

        var indicatorIndex: Int? {
            switch self {
            case .welcome:    return 0
            case .permissions: return 1
            case .hookConfig: return 2
            case .iphone:     return 3
            case .done:       return nil
            }
        }

        static var indicatorCount: Int { 4 }
    }

    @State private var step: Step = .welcome
    @State private var plan: HookInstaller.Plan = HookInstaller.computePlan()
    @State private var applyError: String?
    @State private var applied = false

    let onFinish: () -> Void

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                }
                .frame(maxHeight: .infinity)

                pageIndicator
                    .padding(.bottom, 12)

                Divider().background(Theme.lineSoft)
                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 720, height: 640)
        .background(Theme.bgBase)
        .preferredColorScheme(.dark)
    }

    // MARK: - Step body

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:     welcomeView
        case .permissions: permissionsView
        case .hookConfig:  hookConfigView
        case .iphone:      iphoneView
        case .done:        doneView
        }
    }

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepBadge("1 / 4")
            Text("欢迎使用 CC Peek")
                .font(Theme.ui(24, weight: .bold))
                .foregroundStyle(Theme.fg)
            Text("让 Claude Code 多进程的状态从主屏幕外置出来——菜单栏看一眼就知道哪个进程在等你, 一键就能切到对应终端窗口.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 10) {
                bullet("实时显示所有 Claude Code 进程的状态")
                bullet("等待审批 / 等待输入时菜单栏徽章数字提醒")
                bullet("点卡片直接激活对应终端窗口")
                bullet("iPhone 第二屏（即将上线）随时查看进度")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepBadge("2 / 4")
            Text("系统权限")
                .font(Theme.ui(20, weight: .bold))
                .foregroundStyle(Theme.fg)
            Text("CC Peek 完整运行需要以下权限。现在不必立即授予，使用相关功能时系统会自动弹窗。")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.fgMuted)

            SurfaceCard {
                VStack(spacing: 0) {
                    permissionRow(
                        icon: "play.rectangle",
                        title: "自动化 (Automation)",
                        desc: "用 AppleScript 控制 Terminal / iTerm2 切到目标 tab。拒绝后切换功能不可用，状态显示不受影响。",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                        divider: true
                    )
                    permissionRow(
                        icon: "wifi",
                        title: "本地网络",
                        desc: "iPhone 第二屏的 MultipeerConnectivity 通信所需。",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork",
                        divider: true
                    )
                    permissionRow(
                        icon: "dot.radiowaves.left.and.right",
                        title: "蓝牙",
                        desc: "MultipeerConnectivity 设备发现所需。",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
                        divider: false
                    )
                }
            }

            Text("可以现在就去授权，也可以跳过 — 第一次用到对应功能时系统会自动弹窗。")
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.fgDim)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hookConfigView: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepBadge("3 / 4")
            Text("配置 Claude Code Hook")
                .font(Theme.ui(20, weight: .bold))
                .foregroundStyle(Theme.fg)
            Text("CC Peek 会往 ~/.claude/settings.json 写入 6 个 hook 条目，用来采集进程状态。应用前会自动备份原文件。")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.fgMuted)

            HookDiffView(plan: plan)

            if let err = applyError {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.statusPerm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iphoneView: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepBadge("4 / 4")
            Text("iPhone 第二屏")
                .font(Theme.ui(20, weight: .bold))
                .foregroundStyle(Theme.fg)
            Text("把手机当作 Mac 的常驻第二屏：状态变化实时推到 iPhone，等输入 / 等审批一目了然，再也不用频繁切回 Mac 看。")
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 28) {
                qrPlaceholder
                VStack(alignment: .leading, spacing: 10) {
                    Text("即将上线")
                        .font(Theme.ui(13.5, weight: .semibold))
                        .foregroundStyle(Theme.statusInput)
                    Text("CC Peek 的 iPhone 端目前还在内测，App Store 上架后扫描左侧二维码即可下载。")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        bullet("与 Mac 同 Wi-Fi 网络")
                        bullet("打开 iPhone 端 → 接受配对邀请")
                        bullet("挂在桌面 / 旁边设备常驻显示")
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.oklch(0.30, 0.10, 150, alpha: 0.4))
                Circle()
                    .strokeBorder(Color.oklch(0.50, 0.14, 150, alpha: 0.6), lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.statusActive)
            }
            .frame(width: 64, height: 64)
            .shadow(color: Theme.statusActiveGlow, radius: 12)

            Text("配置完成")
                .font(Theme.ui(22, weight: .bold))
                .foregroundStyle(Theme.fg)
            Text("现在可以开始使用 Claude Code 了，状态会实时出现在菜单栏 popover 里。")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.fgMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - QR placeholder

    private var qrPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.oklch(0.94, 0.005, 250))
            qrPattern
                .padding(18)
            // 半透明覆盖层 + 「未上线」标识
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.oklch(0.10, 0.010, 250, alpha: 0.55))
            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("未上线")
                    .font(Theme.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .frame(width: 160, height: 160)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
        )
    }

    /// 假二维码图案：5×5 finder pattern + 中间 9×9 伪随机方格 (固定种子, 视觉稳定).
    private var qrPattern: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 21  // 21 模块的 QR
            ZStack(alignment: .topLeading) {
                // 三个 finder pattern (左上 / 右上 / 左下), 7×7 模块, 中间 3×3 实心
                finderPattern(at: CGPoint(x: 0, y: 0), cell: cell)
                finderPattern(at: CGPoint(x: cell * 14, y: 0), cell: cell)
                finderPattern(at: CGPoint(x: 0, y: cell * 14), cell: cell)
                // 中间区域：固定模式的伪随机点
                ForEach(0..<14, id: \.self) { row in
                    ForEach(0..<14, id: \.self) { col in
                        if shouldFill(row: row, col: col) {
                            Rectangle()
                                .fill(Color.oklch(0.18, 0.010, 250))
                                .frame(width: cell, height: cell)
                                .offset(x: CGFloat(col + 4) * cell, y: CGFloat(row + 4) * cell)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func finderPattern(at p: CGPoint, cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.oklch(0.18, 0.010, 250))
                .frame(width: cell * 7, height: cell * 7)
            Rectangle()
                .fill(Color.oklch(0.94, 0.005, 250))
                .frame(width: cell * 5, height: cell * 5)
                .offset(x: cell, y: cell)
            Rectangle()
                .fill(Color.oklch(0.18, 0.010, 250))
                .frame(width: cell * 3, height: cell * 3)
                .offset(x: cell * 2, y: cell * 2)
        }
        .offset(x: p.x, y: p.y)
    }

    private func shouldFill(row: Int, col: Int) -> Bool {
        // 固定 hash, 视觉稳定不抖
        ((row * 31 + col * 17 + 7) & 0x3) < 2
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<Step.indicatorCount, id: \.self) { i in
                Capsule()
                    .fill(step.indicatorIndex == i ? Theme.accent : Theme.fgFaint.opacity(0.5))
                    .frame(width: step.indicatorIndex == i ? 16 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(role: .cancel) {
                onFinish()
            } label: {
                Text(step == .done ? "关闭" : "跳过引导")
                    .foregroundStyle(Theme.fgMuted)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Spacer()

            if step != .welcome && step != .done {
                Button("上一步") {
                    if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome, .permissions:
            Button("继续") {
                if let next = Step(rawValue: step.rawValue + 1) { step = next }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        case .hookConfig:
            Button(plan.isNoOp ? "已是最新, 继续" : "应用并继续") {
                applyHook()
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(applied)
        case .iphone:
            Button("完成") { step = .done }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .done:
            Button("开始使用") { onFinish() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func applyHook() {
        let (ok, err) = HookInstaller.apply(plan: plan)
        if ok {
            applied = true
            applyError = nil
            step = .iphone
        } else {
            applyError = err
        }
    }

    // MARK: - Helpers

    private func stepBadge(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10.5, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.fgMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.bgRaised))
            .overlay(Capsule().strokeBorder(Theme.lineSoft, lineWidth: 1))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.accent.opacity(0.7))
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.fgMuted)
        }
    }

    private func permissionRow(icon: String, title: String, desc: String, urlString: String, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .foregroundStyle(Theme.fgMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.ui(13, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    Text(desc)
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.fgDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: 3) {
                        Text("去设置")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if divider {
                DottedDivider().padding(.horizontal, 14)
            }
        }
    }
}

// MARK: - Button styles

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13, weight: .semibold))
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color.oklch(0.55, 0.14, 240, alpha: configuration.isPressed ? 0.85 : 1.0),
                        Color.oklch(0.42, 0.12, 240, alpha: configuration.isPressed ? 0.85 : 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1.0 : 0.45)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(13))
            .foregroundStyle(Theme.fgMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Theme.bgCardPressed : Theme.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.lineSoft, lineWidth: 0.5)
            )
    }
}
