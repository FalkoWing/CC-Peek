import SwiftUI
import CCPeekCore

// 进程卡片 —— 设计稿: cc-peek-ui/components.jsx 的 ProcessCard / CardContent
// iOS-2b: 按压物理感 + 状态点呼吸/脉搏 + 状态切换过渡 + .light haptic
// iOS-2c: duration 每秒刷新 + perm 卡 bleed glow + topEdgeLine edge-pulse

struct ProcessCardView: View {
    let process: TransportMessage.SnapshotProcess
    let variant: CardVariant
    /// 非 nil 时卡片显示"切换失败"错误态(覆盖 header label + 红色 topEdgeLine, 3s 后由调用方清除)
    var switchError: String? = nil
    var onTap: ((String) -> Void)? = nil

    enum CardVariant {
        case compact, wide, tall

        var padding: EdgeInsets {
            switch self {
            case .compact: return .init(top: 16, leading: 18, bottom: 16, trailing: 18)
            case .wide:    return .init(top: 20, leading: 22, bottom: 20, trailing: 22)
            case .tall:    return .init(top: 22, leading: 22, bottom: 22, trailing: 22)
            }
        }
        var nameSize: CGFloat {
            switch self {
            case .compact: return 19
            case .wide:    return 26
            case .tall:    return 28
            }
        }
        var footerSize: CGFloat { self == .compact ? 12 : 13 }
        var termLabel: String { self == .compact ? "TERM" : "TERMINAL" }
        var durationLabel: String { self == .compact ? String(localized: "时长") : String(localized: "已持续") }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap?(process.id)
        } label: {
            ProcessCardSurface(process: process, variant: variant, switchError: switchError)
        }
        .buttonStyle(ProcessCardButtonStyle())
        .disabled(!process.switchable)
        .opacity(process.switchable ? 1.0 : 0.45)
    }
}

// MARK: - 卡片视觉本体（被 ButtonStyle 包裹，通过 environment 读 isPressed）

private struct ProcessCardSurface: View {
    let process: TransportMessage.SnapshotProcess
    let variant: ProcessCardView.CardVariant
    let switchError: String?

    @Environment(\.cardIsPressed) private var isPressed: Bool

    private var status: CardStatusStyle {
        switchError != nil ? .errorStyle : CardStatusStyle.from(process.state)
    }
    private var terminalDisplay: String { process.terminal ?? "—" }
    /// 错误态期间不脉搏(避免抢占注意力), 错误显示完毕由 switchError 清空触发动画恢复.
    private var isPerm: Bool { switchError == nil && process.state == .waitingPermission }

    var body: some View {
        ZStack(alignment: .top) {
            cardBody
            topEdgeLine
                .padding(.horizontal, 12)
            content
                .padding(variant.padding)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .compositingGroup()
        .modifier(CardOuterShadows(isPressed: isPressed))
        .modifier(BleedGlow(active: isPerm))
        .animation(.easeInOut(duration: 0.3), value: process.state)
        .animation(.easeInOut(duration: 0.25), value: switchError != nil)
    }

    // MARK: Body 渐变 + 一圈 stroke 模拟 inset 高光/bevel/底部阴影

    private var cardBody: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .fill(isPressed ? pressedGradient : restGradient)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(strokeGradient, lineWidth: 1)
            )
    }

    private var restGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Theme.bgCardBright,       location: 0),
                .init(color: Theme.bgCard,             location: 0.40),
                .init(color: Theme.cardGradientBottom, location: 1.0)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var pressedGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.bgCardPressed, Theme.cardPressedBottom],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var strokeGradient: LinearGradient {
        if isPressed {
            return LinearGradient(
                stops: [
                    .init(color: Theme.cardInsetShadow2,  location: 0),
                    .init(color: Theme.cardBevel,         location: 0.5),
                    .init(color: Theme.cardHighlightSoft, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            return LinearGradient(
                stops: [
                    .init(color: Theme.cardHighlightStrong, location: 0),
                    .init(color: Theme.cardBevel,           location: 0.5),
                    .init(color: Theme.cardInsetShadow1,    location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: 顶部状态色边线（perm 时 0.9s edge-pulse；其余静态）

    @ViewBuilder
    private var topEdgeLine: some View {
        if isPerm {
            PulsingEdgeLine(color: status.edgeColor)
        } else {
            StaticEdgeLine(color: status.edgeColor, opacity: status.edgeOpacity)
        }
    }

    // MARK: 内容三段

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            name
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(animation: DotAnimation.from(process.state))
            Text(status.label)
                .font(Theme.mono(11, weight: .semibold))
                .tracking(0.44)
                .foregroundStyle(status.textColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var name: some View {
        HStack(spacing: 0) {
            Text(process.name)
                .font(Theme.mono(variant.nameSize, weight: .semibold))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
                .truncationMode(.tail)
                .tracking(-0.19)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(variant.termLabel)
                    .font(Theme.mono(10, weight: .regular))
                    .tracking(0.8)
                    .foregroundStyle(Theme.fgFaint)
                Text(terminalDisplay)
                    .font(Theme.mono(variant.footerSize, weight: .medium))
                    .foregroundStyle(Theme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(variant.durationLabel)
                    .font(Theme.mono(10, weight: .regular))
                    .tracking(0.8)
                    .foregroundStyle(Theme.fgFaint)
                // 每秒刷新 duration text；其余视图不参与 rebuild
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatDuration(secondsBetween: process.stateChangedAt, and: context.date))
                        .font(Theme.mono(variant.footerSize, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - ButtonStyle: 按压物理感 (scale + offset) + isPressed 注入 environment

private struct ProcessCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.cardIsPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct CardIsPressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private extension EnvironmentValues {
    var cardIsPressed: Bool {
        get { self[CardIsPressedKey.self] }
        set { self[CardIsPressedKey.self] = newValue }
    }
}

// MARK: - 外部多层投影（按下时收浅）

private struct CardOuterShadows: ViewModifier {
    let isPressed: Bool

    func body(content: Content) -> some View {
        if isPressed {
            content
                .shadow(color: Theme.cardOuterShadow1, radius: 0.5, x: 0, y: 0)
                .shadow(color: Theme.cardOuterShadow2, radius: 2,   x: 0, y: 1)
        } else {
            content
                .shadow(color: Theme.cardOuterShadow1, radius: 0.5, x: 0, y: 1)
                .shadow(color: Theme.cardOuterShadow2, radius: 4,   x: 0, y: 2)
                .shadow(color: Theme.cardOuterShadow3, radius: 14,  x: 0, y: 6)
        }
    }
}

// MARK: - WaitingPermission bleed glow（卡片整体红色外发光 + ring，1.6s 周期 opacity 呼吸）
//
// 设计稿: styles.css .pcard[data-status="perm"]::after + @keyframes bleed-pulse

private struct BleedGlow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.modifier(BleedGlowActive())
        } else {
            content
        }
    }
}

// 拆成单独 modifier 让 .onAppear / @State 在 active=true 时才被装载
private struct BleedGlowActive: ViewModifier {
    @State private var phase = false

    private let permRing = Color.oklch(0.50, 0.16, 25, alpha: 0.4)
    private let permGlow = Color.oklch(0.70, 0.22, 25, alpha: 0.18)

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(permRing, lineWidth: 1)
                    .opacity(phase ? 1.0 : 0.7)
                    .allowsHitTesting(false)
            )
            .shadow(color: permGlow, radius: 12)   // 0 0 24px ≈ SwiftUI radius 12
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}

// MARK: - 状态视觉映射

private struct CardStatusStyle {
    let label: String
    let textColor: Color
    let edgeColor: Color
    let edgeOpacity: Double

    static func from(_ s: ProcessState) -> CardStatusStyle {
        switch s {
        case .active:
            return .init(label: "ACTIVE",
                         textColor: Theme.statusActive,
                         edgeColor: Theme.statusActive,
                         edgeOpacity: 0.6)
        case .waitingInput:
            return .init(label: "WAITING INPUT",
                         textColor: Theme.statusInput,
                         edgeColor: Theme.statusInput,
                         edgeOpacity: 0.7)
        case .waitingPermission:
            return .init(label: "AWAIT PERMISSION",
                         textColor: Theme.statusPerm,
                         edgeColor: Theme.statusPerm,
                         edgeOpacity: 0.95)
        case .completed, .unknown:
            return .init(label: "UNKNOWN",
                         textColor: Theme.statusUnknown,
                         edgeColor: Theme.statusUnknown,
                         edgeOpacity: 0.4)
        }
    }

    static let errorStyle = CardStatusStyle(
        label: String(localized: "切换失败"),
        textColor: Color.oklch(0.78, 0.18, 25),
        edgeColor: Color.oklch(0.78, 0.18, 25),
        edgeOpacity: 0.95
    )
}

// MARK: - 顶部状态色边线（静态 vs perm 脉搏；用 if/else 切换 view tree 让动画干净启停）

private struct StaticEdgeLine: View {
    let color: Color
    let opacity: Double

    var body: some View {
        edgeRect(color: color)
            .opacity(opacity)
            .frame(height: 1.5)
    }
}

private struct PulsingEdgeLine: View {
    let color: Color

    @State private var phase = false

    var body: some View {
        edgeRect(color: color)
            .opacity(phase ? 1.0 : 0.6)
            .frame(height: 1.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}

private func edgeRect(color: Color) -> some View {
    Rectangle().fill(LinearGradient(
        stops: [
            .init(color: .clear, location: 0),
            .init(color: color,  location: 0.5),
            .init(color: .clear, location: 1)
        ],
        startPoint: .leading, endPoint: .trailing
    ))
}

// MARK: - 状态点动画

// CSS 周期 ↔ SwiftUI duration: autoreverses=true 时, SwiftUI duration = CSS 周期 / 2
// active: 3.4s -> 1.7;  input: 1.6s -> 0.8;  perm: 0.9s -> 0.45
private struct DotAnimation {
    let color: Color
    let glow: Color
    let glowRadius: CGFloat
    let duration: Double
    let scaleMin: CGFloat
    let scaleMax: CGFloat
    let opacityMin: Double
    let opacityMax: Double
    let isStatic: Bool

    static func from(_ s: ProcessState) -> DotAnimation {
        switch s {
        case .active:
            return .init(color: Theme.statusActive, glow: Theme.statusActiveGlow, glowRadius: 4,
                         duration: 1.7,
                         scaleMin: 1.0, scaleMax: 1.06,
                         opacityMin: 0.85, opacityMax: 1.0, isStatic: false)
        case .waitingInput:
            return .init(color: Theme.statusInput, glow: Theme.statusInputGlow, glowRadius: 5,
                         duration: 0.8,
                         scaleMin: 0.95, scaleMax: 1.10,
                         opacityMin: 0.7, opacityMax: 1.0, isStatic: false)
        case .waitingPermission:
            return .init(color: Theme.statusPerm, glow: Theme.statusPermGlow, glowRadius: 7,
                         duration: 0.45,
                         scaleMin: 1.0, scaleMax: 1.18,
                         opacityMin: 0.95, opacityMax: 1.0, isStatic: false)
        case .completed, .unknown:
            return .init(color: Theme.statusUnknown, glow: .clear, glowRadius: 0,
                         duration: 0,
                         scaleMin: 1, scaleMax: 1,
                         opacityMin: 1, opacityMax: 1, isStatic: true)
        }
    }
}

private struct StatusDot: View {
    let animation: DotAnimation
    @State private var phase = false

    var body: some View {
        Circle()
            .fill(animation.color)
            .frame(width: 10, height: 10)
            .scaleEffect(phase ? animation.scaleMax : animation.scaleMin)
            .opacity(phase ? animation.opacityMax : animation.opacityMin)
            .shadow(color: animation.glow, radius: animation.glowRadius)
            .onAppear {
                guard !animation.isStatic else { return }
                withAnimation(.easeInOut(duration: animation.duration).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
            .id(animation.duration)
    }
}

// MARK: - duration formatter（镜像 components.jsx 的 formatDuration）

private func formatDuration(secondsBetween from: Date, and to: Date) -> String {
    let s = max(0, Int(to.timeIntervalSince(from)))
    return formatDuration(s)
}

private func formatDuration(_ seconds: Int) -> String {
    if seconds < 60 { return String(localized: "\(seconds) 秒") }
    let m = seconds / 60
    let rs = seconds % 60
    if m < 60 { return rs > 0 ? String(localized: "\(m) 分 \(rs) 秒") : String(localized: "\(m) 分") }
    let h = m / 60
    let rm = m % 60
    return rm > 0 ? String(localized: "\(h) 小时 \(rm) 分 \(rs) 秒") : String(localized: "\(h) 小时")
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.bgDeepest.ignoresSafeArea()
        VStack(spacing: 12) {
            ProcessCardView(
                process: .init(
                    id: "p1", name: "login-refactor", state: .active,
                    terminal: "iTerm2", switchable: true,
                    startedAt: Date(timeIntervalSinceNow: -1000),
                    stateChangedAt: Date(timeIntervalSinceNow: -412)
                ),
                variant: .compact,
                onTap: { _ in }
            )
            .frame(width: 170, height: 130)

            ProcessCardView(
                process: .init(
                    id: "p3", name: "api-server", state: .waitingPermission,
                    terminal: "Terminal", switchable: true,
                    startedAt: Date(timeIntervalSinceNow: -100),
                    stateChangedAt: Date(timeIntervalSinceNow: -12)
                ),
                variant: .compact,
                onTap: { _ in }
            )
            .frame(width: 170, height: 130)

            ProcessCardView(
                process: .init(
                    id: "p2", name: "data-pipeline", state: .waitingInput,
                    terminal: "Ghostty", switchable: false,
                    startedAt: Date(timeIntervalSinceNow: -200),
                    stateChangedAt: Date(timeIntervalSinceNow: -38)
                ),
                variant: .compact,
                onTap: { _ in }
            )
            .frame(width: 170, height: 130)
        }
        .padding()
    }
}
