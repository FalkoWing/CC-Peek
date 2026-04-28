import SwiftUI
import CCPeekCore

// 公用 SwiftUI 组件 —— Mac 端 popover / settings / onboarding 共用基础视觉
// 设计稿对齐 cc-peek-ui/styles.css + mac-components.jsx

// MARK: - SectionLabel (mono uppercase 小标签)

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.mono(10.5, weight: .regular))
            .tracking(1.26)
            .textCase(.uppercase)
            .foregroundStyle(Theme.fgFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SurfaceCard (.surface 容器，分组用)

struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                LinearGradient(
                    colors: [Color.oklch(0.21, 0.011, 250), Color.oklch(0.18, 0.010, 250)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.cardHighlightSoft, lineWidth: 1)
            )
            .shadow(color: Theme.cardOuterShadow3, radius: 6, x: 0, y: 4)
    }
}

// MARK: - DottedDivider

struct DottedDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(
                GeometryReader { geo in
                    Path { path in
                        let dotSpacing: CGFloat = 4
                        var x: CGFloat = 0
                        while x <= geo.size.width {
                            path.addEllipse(in: CGRect(x: x, y: 0, width: 1, height: 1))
                            x += dotSpacing
                        }
                    }
                    .fill(Theme.lineSoft)
                }
            )
    }
}

// MARK: - DotIndicator (呼吸/脉搏状态点 — 与 iOS 端 ProcessCardView 视觉系统对齐)

struct DotIndicator: View {
    let state: ProcessState
    var size: CGFloat = 10

    var body: some View {
        let anim = DotAnimation.from(state)
        BreathingDot(animation: anim, size: size)
    }
}

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

private struct BreathingDot: View {
    let animation: DotAnimation
    let size: CGFloat
    @State private var phase = false

    var body: some View {
        Circle()
            .fill(animation.color)
            .frame(width: size, height: size)
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

// MARK: - StatusPill

struct StatusPill: View {
    enum Style { case online, offline, neutral, danger, warning }

    let text: String
    var style: Style = .neutral
    var withDot: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if withDot {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: dotColor.opacity(0.6), radius: 2)
            }
            Text(text)
                .font(Theme.mono(10.5, weight: .medium))
                .tracking(0.42)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(bgColor))
        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
    }

    private var textColor: Color {
        switch style {
        case .online:  return Theme.statusActive
        case .offline: return Theme.fgDim
        case .neutral: return Theme.fgMuted
        case .danger:  return Color.oklch(0.85, 0.14, 25)
        case .warning: return Theme.statusInput
        }
    }
    private var dotColor: Color {
        switch style {
        case .online:  return Theme.statusActive
        case .offline: return Theme.fgFaint
        case .neutral: return Theme.fgFaint
        case .danger:  return Theme.statusPerm
        case .warning: return Theme.statusInput
        }
    }
    private var bgColor: Color {
        switch style {
        case .online:  return Color.oklch(0.30, 0.06, 150, alpha: 0.3)
        case .offline: return Color.oklch(0.22, 0.005, 250, alpha: 0.5)
        case .neutral: return Color.oklch(0.22, 0.005, 250, alpha: 0.5)
        case .danger:  return Color.oklch(0.30, 0.10, 25, alpha: 0.3)
        case .warning: return Color.oklch(0.30, 0.06, 75, alpha: 0.3)
        }
    }
    private var borderColor: Color {
        switch style {
        case .online:  return Color.oklch(0.45, 0.10, 150, alpha: 0.4)
        case .offline: return Color.oklch(0.30, 0.005, 250, alpha: 0.5)
        case .neutral: return Color.oklch(0.30, 0.005, 250, alpha: 0.5)
        case .danger:  return Color.oklch(0.55, 0.18, 25, alpha: 0.5)
        case .warning: return Color.oklch(0.45, 0.10, 75, alpha: 0.4)
        }
    }
}

// MARK: - AmbientBackground (深色 popover / window 公用底)

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.bgDeepest
            ZStack {
                RadialGradient(
                    colors: [Color.oklch(0.22, 0.02, 240, alpha: 0.6), .clear],
                    center: UnitPoint(x: 0.2, y: 0),
                    startRadius: 0, endRadius: 360
                )
                RadialGradient(
                    colors: [Color.oklch(0.20, 0.015, 260, alpha: 0.5), .clear],
                    center: UnitPoint(x: 1.0, y: 1.0),
                    startRadius: 0, endRadius: 360
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - ChromeIconButton (统一图标按钮样式)

struct ChromeIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.fgMuted)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [Color.oklch(0.24, 0.012, 248), Color.oklch(0.20, 0.010, 250)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.cardHighlightSoft, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
