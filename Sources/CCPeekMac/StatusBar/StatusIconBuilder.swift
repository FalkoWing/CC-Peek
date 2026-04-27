import AppKit

/// 合成菜单栏图标. 无徽章时返回纯 SF Symbol (template, 自动适配深浅色);
/// 有徽章时合成"图标 + 右上角红色 capsule + 数字". PRD 3.5.2.
enum StatusIconBuilder {
    static func build(waitingCount: Int) -> NSImage {
        guard waitingCount > 0 else {
            let img = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "CC Peek")
                ?? NSImage()
            img.isTemplate = true
            return img
        }

        let label = waitingCount >= 10 ? "9+" : "\(waitingCount)"
        let size = NSSize(width: 22, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            // 底图: eye.fill 取标签色, 适配深浅色
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let baseImg = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)
                .flatMap { $0.withSymbolConfiguration(symbolConfig) }
            if let baseImg {
                NSColor.labelColor.set()
                let baseRect = NSRect(x: 0, y: 1, width: 16, height: 14)
                baseImg.draw(in: baseRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }

            drawBadge(text: label, in: NSRect(x: 10, y: 7, width: 12, height: 11))
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func drawBadge(text: String, in rect: NSRect) {
        NSColor.systemRed.setFill()
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let strSize = str.size()
        let origin = NSPoint(
            x: rect.midX - strSize.width / 2,
            y: rect.midY - strSize.height / 2
        )
        str.draw(at: origin)
    }
}
