#!/bin/bash
# 构建带拖拽安装引导的 macOS DMG:
# 左侧 CCPeek.app, 右侧 Applications 软链接, 背景图展示箭头和 Gatekeeper 提示.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/CCPeek.app"
DMG="$ROOT/build/CCPeek.dmg"
VOLUME_NAME="CC Peek"
TMP_DIR="$(mktemp -d)"
STAGING="$TMP_DIR/staging"
RW_DMG="$TMP_DIR/CCPeek-rw.dmg"
MOUNT_DIR="$TMP_DIR/mount"
BG_SWIFT="$TMP_DIR/make-dmg-background.swift"
BG_PNG="$TMP_DIR/dmg-background.png"

cleanup() {
    if [[ -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
    "$ROOT/scripts/build-app.sh"
fi

if [[ ! -d "$APP" ]]; then
    echo "未找到 app: $APP" >&2
    echo "请先运行 ./scripts/build-app.sh, 或直接运行本脚本自动构建。" >&2
    exit 1
fi

mkdir -p "$STAGING/.background"
ditto "$APP" "$STAGING/CCPeek.app"
ln -s /Applications "$STAGING/Applications"

cat > "$BG_SWIFT" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 720, height: 440)
let image = NSImage(size: size)

func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, width: CGFloat, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineSpacing = 5
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    (text as NSString).draw(
        with: NSRect(x: point.x, y: point.y, width: width, height: 96),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes
    )
}

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.976, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.92, alpha: 1).setStroke()
let divider = NSBezierPath()
divider.move(to: NSPoint(x: 48, y: 120))
divider.line(to: NSPoint(x: 672, y: 120))
divider.lineWidth = 1
divider.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 278, y: 246))
arrow.line(to: NSPoint(x: 442, y: 246))
arrow.lineWidth = 5
NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.68, alpha: 1).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 442, y: 246))
head.line(to: NSPoint(x: 412, y: 268))
head.move(to: NSPoint(x: 442, y: 246))
head.line(to: NSPoint(x: 412, y: 224))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

drawText(
    "拖到 Applications 完成安装",
    at: NSPoint(x: 160, y: 300),
    font: .systemFont(ofSize: 22, weight: .semibold),
    color: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.13, alpha: 1),
    width: 400
)

drawText(
    "安装后打开 CC Peek。如果 macOS 提示无法验证开发者，请到 系统设置 > 隐私与安全性，往下滑找到 CC Peek，点击“仍要打开”。",
    at: NSPoint(x: 90, y: 36),
    font: .systemFont(ofSize: 14, weight: .regular),
    color: NSColor(calibratedRed: 0.23, green: 0.28, blue: 0.31, alpha: 1),
    width: 540
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("无法生成背景图")
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

swift "$BG_SWIFT" "$BG_PNG"
cp "$BG_PNG" "$STAGING/.background/dmg-background.png"

rm -f "$DMG"

echo "==> 创建可写 DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDRW \
    "$RW_DMG" >/dev/null

mkdir -p "$MOUNT_DIR"
echo "==> 挂载并设置 Finder 视图"
hdiutil attach "$RW_DMG" \
    -mountpoint "$MOUNT_DIR" \
    -noautoopen \
    -quiet

osascript <<APPLESCRIPT
set dmgFolder to POSIX file "$MOUNT_DIR" as alias
set backgroundFile to POSIX file "$MOUNT_DIR/.background/dmg-background.png" as alias

tell application "Finder"
    open dmgFolder
    delay 1
    set dmgWindow to container window of dmgFolder
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set bounds of dmgWindow to {120, 120, 840, 560}
    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to backgroundFile
    set position of item "CCPeek.app" of dmgFolder to {180, 210}
    set position of item "Applications" of dmgFolder to {540, 210}
    update dmgFolder without registering applications
    delay 1
    close dmgWindow
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet

echo "==> 压缩 DMG"
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG" >/dev/null

echo "==> 验证 DMG"
hdiutil verify "$DMG"

echo ""
echo "✅ 完成: $DMG"
