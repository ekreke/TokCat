#!/usr/bin/env bash
# 构建 TokCat.app（无 Dock 图标，纯菜单栏）。
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
PRODUCT="TokCat"
BIN=".build/${CONFIG}/${PRODUCT}"
APP="build/${PRODUCT}.app"

# 版本：VERSION 环境变量 > 最近 git tag（去掉前缀 v）> 0.1.0
TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
VERSION="${VERSION:-${TAG#v}}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
echo "==> 版本 ${VERSION} (build ${BUILD_NUMBER})"

echo "==> swift build -c ${CONFIG}"
swift build -c "${CONFIG}" --product "${PRODUCT}"

echo "==> 组装 ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${PRODUCT}"

# SPM 资源包（内置动画素材 + 高亮主题）放进 Contents/Resources。
# 注意：代码通过 Bundle.tokCatResources 按规范位置查找（见 AppBundle.swift），
# 不能拷到 .app 根目录——那会让 codesign 报 unsealed contents 而签名失败。
for bundle in .build/"${CONFIG}"/*.bundle; do
    [ -e "${bundle}" ] || continue
    cp -R "${bundle}" "${APP}/Contents/Resources/"
    echo "    拷贝资源包: $(basename "${bundle}")"
done

cat > "${APP}/Contents/Info.plist" <<PLIST
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
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- 出现在 Launchpad / 应用程序；运行时不显示 Dock 图标（main.swift 里设为 accessory）。 -->
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 签名：优先用 Developer ID（公证前提，带 hardened runtime），否则退回 ad-hoc
# （开机自启 SMAppService 需要已签名）。
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)}"
if [ -n "${IDENTITY}" ]; then
    echo "==> 签名（Developer ID）: ${IDENTITY}"
    codesign --force --deep --options runtime --timestamp --sign "${IDENTITY}" "${APP}"
else
    echo "==> 签名（ad-hoc，未公证）"
    codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || \
        echo "警告: codesign 失败，开机自启可能不可用"
fi

echo "==> 完成: ${APP}"
echo "    运行: open ${APP}"
