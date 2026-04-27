#!/bin/bash
# 把 swift build 产物包装成 CC Peek.app, 含 hook 二进制 + Info.plist + adhoc 签名
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
# 文件名无空格规避 hook 路径含空格的命令解析风险.
# 显示名 "CC Peek" 由 Info.plist CFBundleDisplayName 决定.
APP="$ROOT/build/CCPeek.app"
BIN_DIR=".build/${CONFIG}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

if [[ ! -x "$BIN_DIR/CCPeekMac" || ! -x "$BIN_DIR/CCPeekHook" ]]; then
    echo "构建产物未找到: $BIN_DIR/{CCPeekMac,CCPeekHook}" >&2
    exit 1
fi

echo "==> 准备 .app 结构"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_DIR/CCPeekMac" "$APP/Contents/MacOS/CCPeekMac"
cp "$BIN_DIR/CCPeekHook" "$APP/Contents/MacOS/CCPeekHook"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> adhoc 签名 (开发期足够; 发布前用 Developer ID 替换)"
codesign --force --deep --options runtime \
    --sign - \
    --entitlements Resources/CCPeek.entitlements \
    "$APP"

echo "==> 验证"
codesign -dv "$APP" 2>&1 | head -5

echo ""
echo "==> 注册到 Launch Services (让 SMAppService 能识别)"
LSR="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSR" -f "$APP"

echo ""
echo "✅ 完成: $APP"
echo "运行: open \"$APP\""
echo "或:   \"$APP/Contents/MacOS/CCPeekMac\" --install-hook"
