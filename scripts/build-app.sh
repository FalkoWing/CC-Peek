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

make_spm_resource_app_path() {
    local bundle_name="$1"
    local index="$2"
    local prefix="Contents/Resources/"
    local suffix=".bundle"
    local target_len=${#bundle_name}
    local base_len=$((target_len - ${#prefix} - ${#suffix}))

    if (( base_len < 4 )); then
        echo "SwiftPM 资源 bundle 名太短, 无法安全改写路径: $bundle_name" >&2
        exit 1
    fi

    local counter filler base
    printf -v counter "%03d" "$index"
    filler="spm-resource"
    base="${counter}${filler}"
    while (( ${#base} < base_len )); do
        base="${base}x"
    done
    base="${base:0:$base_len}"

    printf "%s%s%s" "$prefix" "$base" "$suffix"
}

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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM 给依赖生成的 *_*.bundle (本地化字符串等). 它生成的 Bundle.module
# 在 app 内默认查 "$APP/<bundle>", 但 bundle 根目录放非 Contents 文件会导致 codesign 失败.
# 所以这里把 bundle 放到 Contents/Resources, 再把二进制里的查找名改成等长相对路径.
resource_index=0
while IFS= read -r bundle; do
    bundle_name="$(basename "$bundle")"
    app_resource_path="$(make_spm_resource_app_path "$bundle_name" "$resource_index")"

    if (( ${#bundle_name} != ${#app_resource_path} )); then
        echo "内部错误: SwiftPM bundle 路径改写长度不一致: $bundle_name -> $app_resource_path" >&2
        exit 1
    fi

    echo "==> 拷贝 SwiftPM 资源: $bundle_name -> $app_resource_path"
    cp -R "$bundle" "$APP/$app_resource_path"

    for executable in "$APP/Contents/MacOS/"*; do
        [[ -f "$executable" ]] || continue
        if LC_ALL=C grep -a -F -q "$bundle_name" "$executable"; then
            FROM="$bundle_name" TO="$app_resource_path" perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$executable"
            chmod +x "$executable"
        fi
    done

    resource_index=$((resource_index + 1))
done < <(find -L "$BIN_DIR" -maxdepth 1 -name "*.bundle" -type d | sort)

echo "==> adhoc 签名 (开发期足够; 发布前用 Developer ID 替换)"
codesign --force --deep --options runtime \
    --sign - \
    --entitlements Resources/CCPeek.entitlements \
    "$APP"

echo "==> 验证"
codesign --verify --deep --strict --verbose=4 "$APP"
codesign -dv "$APP" 2>&1 | head -5

echo ""
echo "==> 注册到 Launch Services (让 SMAppService 能识别)"
LSR="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSR" -f "$APP"

echo ""
echo "✅ 完成: $APP"
echo "运行: open \"$APP\""
echo "或:   \"$APP/Contents/MacOS/CCPeekMac\" --install-hook"
