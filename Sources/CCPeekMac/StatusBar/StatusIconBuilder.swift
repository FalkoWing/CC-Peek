import AppKit
import SwiftUI

/// 合成菜单栏图标 (PRD 3.5.2 / MacUI-2 设计稿对齐).
///
/// 主图：Twin Beacons glyph (左右双端点 + 上下连接弧线，对齐 cc-peek-ui/icon-lab.html 方案 02)
/// 三层徽章 (按优先级互斥渲染):
///   - 数字徽章 (右上, 待处理进程数 1-9 / "9+")
///   - Hook 错误红点 (右上, 仅 waitingCount=0 时)
///   - 连接绿点 (右下, 仅 waitingCount=0 时)
/// 数字徽章存在时不画连接绿点 (避免菜单栏小尺寸下重叠不清)；
/// 红点和绿点可同时出现于不同位置.
///
/// 深浅色适配：合成图 isTemplate=false (徽章是彩色)，主图根据 NSApp.effectiveAppearance 切色.
/// StatusBarController 监听 effectiveAppearance KVO 触发重绘.
enum StatusIconBuilder {
    static func build(
        waitingCount: Int,
        hasConnectedPhone: Bool = false,
        hasHookError: Bool = false,
        appearance: NSAppearance? = nil
    ) -> NSImage {
        let isDark = (appearance ?? NSApp.effectiveAppearance)
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // 24×20 画布：比眼睛主图大一圈，留出徽章 outline 描边的 1px 边距
        // (徽章外圈 insetBy(-1,-1) 会向外扩 1px，画布太小会被裁切)
        let size = NSSize(width: 24, height: 20)
        let img = NSImage(size: size, flipped: false) { _ in
            drawTwinBeaconsGlyph(in: size, isDark: isDark)

            if waitingCount > 0 {
                drawNumberBadge(count: waitingCount, in: size, isDark: isDark)
                if hasHookError { drawErrorDot(in: size, isDark: isDark) }
            } else {
                if hasHookError {
                    drawErrorDot(in: size, isDark: isDark)
                } else if hasConnectedPhone {
                    drawConnectedDot(in: size, isDark: isDark)
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - 主图：Twin Beacons glyph

    private static func drawTwinBeaconsGlyph(in size: NSSize, isDark: Bool) {
        let main = isDark
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.85)

        // 左右两个端点代表 Mac / iPhone；上下弧线代表近场连接。
        let leftBeacon = NSBezierPath(ovalIn: NSRect(x: 4.5, y: 7.3, width: 5.4, height: 5.4))
        leftBeacon.lineWidth = 1.55
        leftBeacon.lineCapStyle = .round
        leftBeacon.lineJoinStyle = .round
        main.setStroke()
        leftBeacon.stroke()

        let rightBeacon = NSBezierPath(ovalIn: NSRect(x: 14.1, y: 7.3, width: 5.4, height: 5.4))
        rightBeacon.lineWidth = 1.55
        rightBeacon.lineCapStyle = .round
        rightBeacon.lineJoinStyle = .round
        rightBeacon.stroke()

        let bridge = NSBezierPath()
        bridge.move(to: NSPoint(x: 9.9, y: 10))
        bridge.line(to: NSPoint(x: 14.1, y: 10))
        bridge.lineWidth = 1.35
        bridge.lineCapStyle = .round
        bridge.lineJoinStyle = .round
        bridge.stroke()

        let topArc = NSBezierPath()
        topArc.move(to: NSPoint(x: 5.2, y: 14.4))
        topArc.curve(
            to: NSPoint(x: 12.0, y: 17.0),
            controlPoint1: NSPoint(x: 7.0, y: 16.1),
            controlPoint2: NSPoint(x: 9.2, y: 17.0)
        )
        topArc.curve(
            to: NSPoint(x: 18.8, y: 14.4),
            controlPoint1: NSPoint(x: 14.8, y: 17.0),
            controlPoint2: NSPoint(x: 17.0, y: 16.1)
        )
        topArc.lineWidth = 1.15
        topArc.lineCapStyle = .round
        topArc.lineJoinStyle = .round
        topArc.stroke()

        let bottomArc = NSBezierPath()
        bottomArc.move(to: NSPoint(x: 5.2, y: 5.6))
        bottomArc.curve(
            to: NSPoint(x: 12.0, y: 3.0),
            controlPoint1: NSPoint(x: 7.0, y: 3.9),
            controlPoint2: NSPoint(x: 9.2, y: 3.0)
        )
        bottomArc.curve(
            to: NSPoint(x: 18.8, y: 5.6),
            controlPoint1: NSPoint(x: 14.8, y: 3.0),
            controlPoint2: NSPoint(x: 17.0, y: 3.9)
        )
        bottomArc.lineWidth = 1.15
        bottomArc.lineCapStyle = .round
        bottomArc.lineJoinStyle = .round
        bottomArc.stroke()
    }

    // MARK: - 数字徽章 (右上)

    private static func drawNumberBadge(count: Int, in size: NSSize, isDark: Bool) {
        let label = count >= 10 ? "9+" : "\(count)"
        let font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(red: 0.10, green: 0.06, blue: 0.0, alpha: 1.0), // 偏黑暖色
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let textSize = str.size()

        // 圆角矩形 (capsule)：宽度跟随文字，至少 12，高度 11，靠右上 (留 1px outline 边距)
        let badgeWidth = max(12, textSize.width + 6)
        let badgeRect = NSRect(
            x: size.width - badgeWidth - 1,
            y: size.height - 11 - 1,
            width: badgeWidth,
            height: 11
        )

        // 一圈与 menubar 同色的描边 (把徽章和主图分开)
        let outlineColor: NSColor = isDark
            ? NSColor.black.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.95)
        let outlineRect = badgeRect.insetBy(dx: -1, dy: -1)
        let outlinePath = NSBezierPath(roundedRect: outlineRect, xRadius: outlineRect.height/2, yRadius: outlineRect.height/2)
        outlineColor.setFill()
        outlinePath.fill()

        // amber 背景
        let amber = NSColor(Color.oklch(0.80, 0.16, 75))
        let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height/2, yRadius: badgeRect.height/2)
        amber.setFill()
        bgPath.fill()

        // 文字居中
        let origin = NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2 + 0.5
        )
        str.draw(at: origin)
    }

    // MARK: - 连接绿点 (右下)

    private static func drawConnectedDot(in size: NSSize, isDark: Bool) {
        // 留 1px outline 边距，避免外圈描边贴到画布边
        let dotRect = NSRect(x: size.width - 7 - 1, y: 1, width: 7, height: 7)

        // 外圈描边 (与 menubar 同色，把绿点与主图分开)
        let outlineColor: NSColor = isDark
            ? NSColor.black.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.95)
        let outlineRect = dotRect.insetBy(dx: -1, dy: -1)
        outlineColor.setFill()
        NSBezierPath(ovalIn: outlineRect).fill()

        let green = NSColor(Color.oklch(0.78, 0.16, 150))
        green.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    // MARK: - Hook 错误红点 (右上)

    private static func drawErrorDot(in size: NSSize, isDark: Bool) {
        // 留 1px outline 边距
        let dotRect = NSRect(x: size.width - 7 - 1, y: size.height - 7 - 1, width: 7, height: 7)

        let outlineColor: NSColor = isDark
            ? NSColor.black.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.95)
        let outlineRect = dotRect.insetBy(dx: -1, dy: -1)
        outlineColor.setFill()
        NSBezierPath(ovalIn: outlineRect).fill()

        let red = NSColor(Color.oklch(0.70, 0.20, 25))
        red.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}
