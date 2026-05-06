#!/bin/bash
# 把 swift build 产物包装成 CC Peek.app, 含 hook 二进制 + Info.plist + 签名.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CODESIGN_TIMESTAMP="${CODESIGN_TIMESTAMP:-}"
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
mkdir -p "$APP/Contents/Frameworks"

cp "$BIN_DIR/CCPeekMac" "$APP/Contents/MacOS/CCPeekMac"
cp "$BIN_DIR/CCPeekHook" "$APP/Contents/MacOS/CCPeekHook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SPARKLE_FRAMEWORK="$(find -L .build/artifacts -path "*/Sparkle.framework" -type d | head -n 1 || true)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework 未找到, 请先确认 SwiftPM binary artifact 已下载" >&2
    exit 1
fi
echo "==> 拷贝 Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/CCPeekMac" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/CCPeekMac"
fi

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

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> adhoc 签名 (开发期)"
else
    echo "==> Developer ID 签名: $SIGN_IDENTITY"
fi
# 公共选项: 不带 --deep. Apple 已 deprecated --deep, 且会用主 app entitlements
# 覆盖内嵌 helper 的 entitlements, 破坏 Sparkle Updater/XPC 行为.
codesign_common=(--force --options runtime)
if [[ "$CODESIGN_TIMESTAMP" == "none" ]]; then
    codesign_common+=(--timestamp=none)
elif [[ -n "$CODESIGN_TIMESTAMP" ]]; then
    codesign_common+=(--timestamp="$CODESIGN_TIMESTAMP")
fi

# Sparkle SwiftPM 分发包是 Sparkle 团队用自家证书 adhoc 预签的.
# Apple 公证要求所有内嵌 binary 用提交方的 Developer ID 重签, 但内嵌 helper
# 各有自己的 entitlements (Autoupdate / Updater.app / XPCServices), 主 app 的
# entitlements 套上去会破坏 helper 行为, 必须 --preserve-metadata 保留原 entitlements.
# 顺序: 先内层, 后 framework 自身, 最后主 app — codesign 由内向外才能正确算 hash.
SP_FW="$APP/Contents/Frameworks/Sparkle.framework"
echo "==> 重签 Sparkle 内嵌组件 (preserve entitlements)"
sparkle_nested=(
    "$SP_FW/Versions/B/XPCServices/Downloader.xpc"
    "$SP_FW/Versions/B/XPCServices/Installer.xpc"
    "$SP_FW/Versions/B/Updater.app"
    "$SP_FW/Versions/B/Autoupdate"
)
for nested in "${sparkle_nested[@]}"; do
    if [[ -e "$nested" ]]; then
        codesign "${codesign_common[@]}" \
            --preserve-metadata=identifier,entitlements,flags \
            --sign "$SIGN_IDENTITY" \
            "$nested"
    fi
done

echo "==> 重签 Sparkle.framework"
codesign "${codesign_common[@]}" \
    --sign "$SIGN_IDENTITY" \
    "$SP_FW"

# SwiftPM 生成的本地化资源 bundle 没有可执行代码, 但 --strict 验证会检查
# 它们的签名状态. 单独签一遍避免后续 verify 失败.
for spm_bundle in "$APP/Contents/Resources/"*.bundle; do
    [[ -e "$spm_bundle" ]] || continue
    codesign "${codesign_common[@]}" \
        --sign "$SIGN_IDENTITY" \
        "$spm_bundle"
done

echo "==> 签主 app"
codesign "${codesign_common[@]}" \
    --sign "$SIGN_IDENTITY" \
    --entitlements Resources/CCPeek.entitlements \
    "$APP"

echo "==> 验证"
codesign --verify --deep --strict --verbose=4 "$APP"
codesign_info="$(codesign -dv "$APP" 2>&1 || true)"
printf "%s\n" "$codesign_info" | sed -n '1,5p'

echo ""
echo "==> 注册到 Launch Services (让 SMAppService 能识别)"
LSR="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSR" -f "$APP"

echo ""
echo "✅ 完成: $APP"
echo "运行: open \"$APP\""
echo "或:   \"$APP/Contents/MacOS/CCPeekMac\" --install-hook"
