import SwiftUI
import AppKit
import CoreImage
import CCPeekCore

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case hookConfig
        case iphone

        static var indicatorCount: Int { 4 }
    }

    @State private var step: Step = .welcome
    @State private var plan: HookInstaller.Plan = HookInstaller.computePlan()
    @State private var applyError: String?
    @State private var applied = false

    private static let appStoreURLString = "https://apps.apple.com/app/cc-peek/id6766753337"
    private static let appStoreQRCodeImage = makeQRCodeImage(from: appStoreURLString)

    let onFinish: () -> Void

    var body: some View {
        ZStack {
            AmbientBackground()
            content
        }
        .frame(width: 640, height: 520)
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
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 18)

            heroIcon

            VStack(spacing: 10) {
                Text("CC Peek")
                    .font(Theme.ui(28, weight: .bold))
                    .foregroundStyle(Theme.fg)
                Text("Claude Code 桌面第二屏")
                    .font(Theme.ui(16, weight: .medium))
                    .foregroundStyle(Theme.fgMuted)
                Text("实时监控你的 Claude Code 进程状态，\niPhone 放电脑旁边就能随时感知。")
                    .font(Theme.ui(13.5))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.fgDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }

            Button {
                step = .permissions
            } label: {
                HStack(spacing: 6) {
                    Text("开始")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(ChromeButtonStyle(kind: .primary, horizontalPadding: 18, verticalPadding: 10))
            .keyboardShortcut(.defaultAction)

            Spacer()
            pageDots(current: step.rawValue)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("权限设置")
                    .font(Theme.ui(20, weight: .bold))
                    .foregroundStyle(Theme.fg)
                Text("为了正常工作，CC Peek 需要以下系统权限。可以稍后单独设置。")
                    .font(Theme.ui(13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                permissionCard(
                    icon: "dot.radiowaves.left.and.right",
                    title: String(localized: "蓝牙"),
                    desc: "CC Peek 需要蓝牙来发现和连接你的 iPhone",
                    urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
                )
                permissionCard(
                    icon: "wifi",
                    title: String(localized: "本地网络"),
                    desc: "通过本地网络与 iPhone 通信，传输进程状态信息",
                    urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
                )
                permissionCard(
                    icon: "play.rectangle",
                    title: String(localized: "自动化"),
                    desc: "用于自动切换终端窗口到对应的 Claude Code 进程",
                    urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )
            }

            Spacer(minLength: 0)

            bottomControls(
                leftTitle: "稍后设置",
                leftAction: { step = .hookConfig },
                right: AnyView(
                    Button {
                        step = .hookConfig
                    } label: {
                        HStack(spacing: 6) {
                            Text("下一步")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(ChromeButtonStyle(kind: .secondary))
                    .keyboardShortcut(.defaultAction)
                ),
                pageIndex: step.rawValue
            )
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hookConfigView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("配置 Claude Code 事件监听")
                    .font(Theme.ui(20, weight: .bold))
                    .foregroundStyle(Theme.fg)
                Text("CC Peek 需要在 Claude Code 的配置文件中添加事件监听钩子。以下是即将进行的变更：")
                    .font(Theme.ui(13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HookDiffView(plan: plan)

            if let err = applyError {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(Theme.ui(11.5, weight: .medium))
                    .foregroundStyle(Theme.statusPerm)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            bottomControls(
                leftTitle: "取消 — 功能将受限",
                leftAction: onFinish,
                right: AnyView(
                    Button {
                        applyHook()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: plan.isNoOp ? "chevron.right" : "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text(plan.isNoOp ? "已是最新，继续" : "确认并应用")
                        }
                    }
                    .buttonStyle(ChromeButtonStyle(kind: .success, horizontalPadding: 18))
                    .keyboardShortcut(.defaultAction)
                    .disabled(applied)
                ),
                pageIndex: step.rawValue,
                leftIsCancel: true
            )
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var iphoneView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Text("在 iPhone 上安装 CC Peek")
                    .font(Theme.ui(22, weight: .bold))
                    .foregroundStyle(Theme.fg)
                Text("扫描二维码，或在 iPhone 上打开 App Store 链接下载。")
                    .font(Theme.ui(13.5))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.fgMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            appStoreQRCode

            Button {
                onFinish()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("完成 — 进入 Dashboard")
                }
            }
            .buttonStyle(ChromeButtonStyle(kind: .secondary, horizontalPadding: 18, verticalPadding: 10))
            .keyboardShortcut(.defaultAction)

            Text("完成后将开启开机自启 · 可在设置 → 通用关闭")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.fgFaint)

            Spacer()
            pageDots(current: step.rawValue)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Visual pieces

    private var heroIcon: some View {
        Image(nsImage: AppIconLoader.image())
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.oklch(0.78, 0.18, 130, alpha: 0.26), lineWidth: 0.8)
            )
            .shadow(color: Color.oklch(0.78, 0.18, 130, alpha: 0.34), radius: 22)
            .shadow(color: Color.oklch(0.04, 0, 0, alpha: 0.70), radius: 14, y: 8)
        .frame(width: 96, height: 96)
    }

    private var appStoreQRCode: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.oklch(0.96, 0.005, 250))
                .shadow(color: Color.oklch(0.04, 0, 0, alpha: 0.5), radius: 12, y: 8)
            if let image = Self.appStoreQRCodeImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            } else {
                Text(Self.appStoreURLString)
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Color.oklch(0.18, 0.010, 250))
                    .multilineTextAlignment(.center)
                    .padding(18)
            }
        }
        .frame(width: 180, height: 180)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
        )
    }

    private static func makeQRCodeImage(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else {
            return nil
        }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Controls

    private func permissionCard(icon: String, title: String, desc: String, urlString: String) -> some View {
        SurfaceCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.bgRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Theme.lineSoft, lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Theme.fgMuted)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.ui(13.5, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                    Text(desc)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.fgDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button("授权") {
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(ChromeButtonStyle(kind: .secondary, horizontalPadding: 12, verticalPadding: 6, fontSize: 12))
            }
            .padding(14)
        }
    }

    private func bottomControls(
        leftTitle: String,
        leftAction: @escaping () -> Void,
        right: AnyView,
        pageIndex: Int,
        leftIsCancel: Bool = false
    ) -> some View {
        ZStack {
            pageDots(current: pageIndex)
            HStack {
                if leftIsCancel {
                    Button(leftTitle, action: leftAction)
                        .buttonStyle(TextButtonStyle())
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button(leftTitle, action: leftAction)
                        .buttonStyle(TextButtonStyle())
                }
                Spacer()
                right
            }
        }
        .frame(height: 38)
    }

    private func pageDots(current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<Step.indicatorCount, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.fgMuted : Color.oklch(0.35, 0.012, 250))
                    .frame(width: i == current ? 16 : 5, height: 5)
                    .animation(.spring(response: 0.30, dampingFraction: 0.82), value: current)
            }
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
}

// MARK: - App icon

private enum AppIconLoader {
    static func image() -> NSImage {
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let image = NSImage(contentsOfFile: "Resources/AppIcon.png") {
            return image
        }
        return NSApp.applicationIconImage
    }
}

// MARK: - Button styles

private struct ChromeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, success }

    @Environment(\.isEnabled) private var isEnabled

    var kind: Kind
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 9
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(fontSize, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                LinearGradient(
                    colors: gradientColors(isPressed: configuration.isPressed),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.6)
            )
            .shadow(color: Color.oklch(0.04, 0, 0, alpha: configuration.isPressed ? 0.25 : 0.60), radius: 3, y: 1)
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .secondary: return Theme.fg
        case .success:             return Color.oklch(0.96, 0.02, 150)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color.oklch(0.70, 0.14, 240, alpha: 0.55)
        case .secondary:
            return Theme.cardHighlightSoft
        case .success:
            return Color.oklch(0.70, 0.14, 150, alpha: 0.55)
        }
    }

    private func gradientColors(isPressed: Bool) -> [Color] {
        let alpha = isPressed ? 0.86 : 1.0
        switch kind {
        case .primary:
            return [
                Color.oklch(0.55, 0.14, 240, alpha: alpha),
                Color.oklch(0.42, 0.12, 240, alpha: alpha),
            ]
        case .secondary:
            return [
                Color.oklch(isPressed ? 0.21 : 0.24, 0.012, 248),
                Color.oklch(isPressed ? 0.18 : 0.20, 0.010, 250),
            ]
        case .success:
            return [
                Color.oklch(0.55, 0.14, 150, alpha: alpha),
                Color.oklch(0.42, 0.12, 150, alpha: alpha),
            ]
        }
    }
}

private struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12.5, weight: .regular))
            .foregroundStyle(Theme.fgMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.65 : 1.0)
    }
}
