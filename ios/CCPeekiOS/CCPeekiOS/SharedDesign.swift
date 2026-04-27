import SwiftUI

// 公用设计组件 —— 设计稿 cc-peek-ui/components.jsx 里的 SectionLabel / Surface / DeviceRow / SettingsRow / iOS Toggle
// 跨页面复用 (设置页 / DeviceSwitcher / PairFound)

// MARK: - SectionLabel (mono uppercase 小标签)

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.mono(10.5, weight: .regular))
            .tracking(1.26)              // 0.12em @ 10.5pt
            .foregroundStyle(Theme.fgFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .padding(.horizontal, 16)
    }
}

// MARK: - Surface (.surface 容器)

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

// MARK: - DottedDivider (设计稿 .divider-dotted)

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
            .padding(.horizontal, 16)
    }
}

// MARK: - DeviceRow (设备列表的一行)

struct DeviceRow: View {
    let name: String
    let subtitle: String
    var statusBadge: StatusBadge?    // nil = 不显示徽章
    var trailingChevron: Bool = false
    var onTap: (() -> Void)? = nil

    enum StatusBadge: Equatable { case current, online, offline }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.oklch(0.20, 0.010, 250))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.lineSoft, lineWidth: 1)
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "macbook")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Theme.fgMuted)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(Theme.ui(14, weight: .semibold))
                            .foregroundStyle(Theme.fg)
                        if statusBadge == .current {
                            badgePill(text: "已连接", greenStyle: true, withDot: true)
                        }
                    }
                    Text(subtitle)
                        .font(Theme.mono(11.5, weight: .regular))
                        .foregroundStyle(Theme.fgDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if statusBadge == .online {
                    badgePill(text: "在线", greenStyle: true)
                } else if statusBadge == .offline {
                    badgePill(text: "离线", greenStyle: false)
                }

                if trailingChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.fgFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    @ViewBuilder
    private func badgePill(text: String, greenStyle: Bool, withDot: Bool = false) -> some View {
        HStack(spacing: 4) {
            if withDot {
                Circle()
                    .fill(Theme.statusActive)
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.statusActiveGlow, radius: 2)
            }
            Text(text)
                .font(Theme.mono(10.5, weight: .medium))
                .tracking(0.42)
        }
        .foregroundStyle(greenStyle ? Theme.statusActive : Theme.fgDim)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(greenStyle
                ? Color.oklch(0.30, 0.06, 150, alpha: 0.3)
                : Color.oklch(0.22, 0.005, 250, alpha: 0.5))
        )
        .overlay(
            Capsule().strokeBorder(greenStyle
                ? Color.oklch(0.45, 0.10, 150, alpha: 0.4)
                : Color.oklch(0.30, 0.005, 250, alpha: 0.5), lineWidth: 1)
        )
    }
}

// MARK: - SettingsRow (设置页一行)

struct SettingsRow<Trailing: View>: View {
    let leadingSystemImage: String?
    let title: String
    let subtitle: String?
    let divider: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(leadingSystemImage: String? = nil,
         title: String,
         subtitle: String? = nil,
         divider: Bool = true,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.leadingSystemImage = leadingSystemImage
        self.title = title
        self.subtitle = subtitle
        self.divider = divider
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon = leadingSystemImage {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Theme.fgMuted)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.ui(14, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    if let s = subtitle {
                        Text(s)
                            .font(Theme.mono(11.5, weight: .regular))
                            .foregroundStyle(Theme.fgDim)
                    }
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            if divider { DottedDivider() }
        }
    }
}

// 无 trailing 时的便捷 init
extension SettingsRow where Trailing == EmptyView {
    init(leadingSystemImage: String? = nil,
         title: String,
         subtitle: String? = nil,
         divider: Bool = true) {
        self.init(leadingSystemImage: leadingSystemImage,
                  title: title,
                  subtitle: subtitle,
                  divider: divider) { EmptyView() }
    }
}

// MARK: - iOS Style Toggle (自定义视觉，匹配设计稿 .ios-toggle)

struct IOSToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn
                    ? LinearGradient(
                        colors: [Color.oklch(0.55, 0.14, 150), Color.oklch(0.45, 0.12, 150)],
                        startPoint: .top, endPoint: .bottom)
                    : LinearGradient(
                        colors: [Color.oklch(0.18, 0.008, 250), Color.oklch(0.22, 0.010, 250)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    Capsule().strokeBorder(isOn
                        ? Color.oklch(0.65, 0.14, 150, alpha: 0.6)
                        : Color.oklch(0.28, 0.012, 250, alpha: 0.6), lineWidth: 1)
                )
                .frame(width: 44, height: 26)

            Circle()
                .fill(LinearGradient(
                    colors: [Color.oklch(0.85, 0.005, 250), Color.oklch(0.75, 0.006, 250)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 22, height: 22)
                .shadow(color: Color.oklch(0.05, 0.005, 250, alpha: 0.6), radius: 1, x: 0, y: 1)
                .padding(2)
        }
        .frame(width: 44, height: 26)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isOn)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isOn.toggle()
        }
    }
}

// MARK: - Ambient background (沉浸式深色页面公用底)

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.bgDeepest
            ambientGradient
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var ambientGradient: some View {
        ZStack {
            RadialGradient(
                colors: [Color.oklch(0.22, 0.02, 240, alpha: 0.6), .clear],
                center: UnitPoint(x: 0.2, y: 0),
                startRadius: 0,
                endRadius: 360
            )
            RadialGradient(
                colors: [Color.oklch(0.20, 0.015, 260, alpha: 0.5), .clear],
                center: UnitPoint(x: 1.0, y: 1.0),
                startRadius: 0,
                endRadius: 360
            )
        }
    }
}

// MARK: - Chrome icon button (36x36 圆角按钮)

struct ChromeIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.fgMuted)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: [Color.oklch(0.24, 0.012, 248), Color.oklch(0.20, 0.010, 250)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                        .strokeBorder(Theme.cardHighlightSoft, lineWidth: 0.5)
                )
                .shadow(color: Theme.cardOuterShadow1, radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
