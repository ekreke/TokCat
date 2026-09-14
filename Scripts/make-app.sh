#!/usr/bin/env bash
# 构建 TokCat.app（无 Dock 图标，纯菜单栏）。
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
PRODUCT="TokCat"
BIN=".build/${CONFIG}/${PRODUCT}"
APP="build/${PRODUCT}.app"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}" --product "${PRODUCT}"

echo "==> 组装 ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${PRODUCT}"

# SPM 资源包（内置动画素材）需要放进 Contents/Resources，Bundle.module 才能找到
for bundle in .build/"${CONFIG}"/*.bundle; do
    [ -e "${bundle}" ] || continue
    cp -R "${bundle}" "${APP}/Contents/Resources/"
    echo "    拷贝资源包: $(basename "${bundle}")"
done

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TokCat</string>
    <key>CFBundleDisplayName</key>
    <string>TokCat</string>
    <key>CFBundleIdentifier</key>
    <string>com.ekreke.tokcat</string>
    <key>CFBundleExecutable</key>
    <string>TokCat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# ad-hoc 签名（开机自启 SMAppService 需要已签名）
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || \
    echo "警告: codesign 失败，开机自启可能不可用"

echo "==> 完成: ${APP}"
echo "    运行: open ${APP}"
