import SwiftUI

// Design tokens 移植自 cc-peek-ui/styles.css（与 iOS 端 Theme.swift 保持一致）
//
// 颜色用 oklch 字面值描述，运行时换算成 sRGB —— 设计稿改值时直接复制粘贴
// CSS 写法 `oklch(L C h)` 对应 Swift 写法 `Color.oklch(L, C, h)`

enum Theme {

    // MARK: - 背景（cool deep neutrals, hue ≈ 250）

    static let bgDeepest    = Color.oklch(0.13, 0.008, 250)
    static let bgBase       = Color.oklch(0.16, 0.008, 250)
    static let bgRaised     = Color.oklch(0.20, 0.010, 250)
    static let bgCard       = Color.oklch(0.23, 0.012, 248)
    static let bgCardBright = Color.oklch(0.27, 0.014, 248)
    static let bgCardPressed = Color.oklch(0.18, 0.010, 250)

    static let cardGradientBottom = Color.oklch(0.20, 0.011, 250)
    static let cardPressedBottom  = Color.oklch(0.16, 0.010, 250)

    // MARK: - 线条

    static let lineSoft   = Color.oklch(0.30, 0.012, 250, alpha: 0.5)
    static let lineSharp  = Color.oklch(0.36, 0.014, 250, alpha: 0.7)
    static let lineBright = Color.oklch(0.45, 0.016, 250, alpha: 0.6)

    // MARK: - 文字

    static let fg       = Color.oklch(0.96, 0.005, 250)
    static let fgMuted  = Color.oklch(0.72, 0.010, 250)
    static let fgDim    = Color.oklch(0.55, 0.010, 250)
    static let fgFaint  = Color.oklch(0.40, 0.010, 250)

    // MARK: - 状态色

    static let statusActive     = Color.oklch(0.78, 0.16, 150)
    static let statusActiveGlow = Color.oklch(0.78, 0.18, 150, alpha: 0.45)
    static let statusActiveDim  = Color.oklch(0.58, 0.12, 150)

    static let statusInput      = Color.oklch(0.80, 0.16, 75)
    static let statusInputGlow  = Color.oklch(0.80, 0.18, 75, alpha: 0.45)
    static let statusInputDim   = Color.oklch(0.60, 0.13, 75)

    static let statusPerm       = Color.oklch(0.70, 0.20, 25)
    static let statusPermGlow   = Color.oklch(0.70, 0.22, 25, alpha: 0.55)
    static let statusPermDim    = Color.oklch(0.50, 0.16, 25)

    static let statusUnknown    = Color.oklch(0.60, 0.010, 250)
    static let statusUnknownDim = Color.oklch(0.42, 0.010, 250)

    // MARK: - Accent

    static let accent    = Color.oklch(0.72, 0.14, 240)
    static let accentDim = Color.oklch(0.50, 0.10, 240)

    // MARK: - 卡片键帽视觉用到的细颗粒色

    static let cardHighlightStrong = Color.oklch(0.50, 0.02, 250, alpha: 0.5)
    static let cardHighlightSoft   = Color.oklch(0.55, 0.02, 250, alpha: 0.25)
    static let cardBevel           = Color.oklch(0.30, 0.012, 250, alpha: 0.4)
    static let cardInsetShadow1    = Color.oklch(0.10, 0.008, 250, alpha: 0.6)
    static let cardInsetShadow2    = Color.oklch(0.08, 0.008, 250, alpha: 0.8)
    static let cardOuterShadow1    = Color.oklch(0.06, 0.005, 250, alpha: 1.0)
    static let cardOuterShadow2    = Color.oklch(0.05, 0.005, 250, alpha: 0.7)
    static let cardOuterShadow3    = Color.oklch(0.04, 0.005, 250, alpha: 0.5)

    // MARK: - 圆角

    static let cardRadius:   CGFloat = 18
    static let buttonRadius: CGFloat = 10
    static let popoverRadius: CGFloat = 12
    static let pillRadius:   CGFloat = 999

    // MARK: - 字体（暂用系统字体；MacUI-4a 后置打包 Inter / JetBrains Mono）

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - oklch → sRGB
// 公式来自 https://bottosson.github.io/posts/oklab/ + CSS Color Module Level 4
extension Color {
    static func oklch(_ L: Double, _ C: Double, _ h: Double, alpha: Double = 1.0) -> Color {
        let hRad = h * .pi / 180
        let a = C * cos(hRad)
        let b = C * sin(hRad)

        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b

        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_

        let rLin =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let gLin = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bLin = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        return Color(
            .sRGB,
            red: linearToSRGB(rLin),
            green: linearToSRGB(gLin),
            blue: linearToSRGB(bLin),
            opacity: alpha
        )
    }

    private static func linearToSRGB(_ x: Double) -> Double {
        let c = max(0, min(1, x))
        return c <= 0.0031308
            ? c * 12.92
            : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }
}
