#!/usr/bin/env bash
# 构建 TokCat.app 并打包为 DMG（拖拽安装到 /Applications）。
#
# 环境变量：
#   VERSION          版本号（默认取最近 git tag，回退 0.1.0）
#   CODESIGN_IDENTITY 签名身份（默认自动探测 Developer ID，找不到则 ad-hoc）
#   NOTARY_PROFILE   notarytool keychain profile（提供则对 DMG 做公证）
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
VERSION="${VERSION#v}"
VERSION="${VERSION:-0.1.0}"
APP="build/TokCat.app"
DMG="build/TokCat-${VERSION}.dmg"

# 1) 构建 + 签名 app（make-app.sh 内部复用同一套签名逻辑）
VERSION="$VERSION" ./Scripts/make-app.sh release

# 2) 解析签名身份
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)}"

# 3) staging：app + /Applications 软链
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 4) 生成 DMG
echo "==> 生成 ${DMG}"
rm -f "$DMG"
hdiutil create -volname TokCat -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# 5) 签名 DMG（有身份时）
if [ -n "${IDENTITY}" ]; then
    echo "==> 签名 DMG: ${IDENTITY}"
    codesign --force --timestamp --sign "${IDENTITY}" "$DMG"
fi

# 6) 公证（需身份 + keychain profile）
if [ -n "${IDENTITY}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> 公证（profile: ${NOTARY_PROFILE}）"
    xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "$DMG"
    spctl -a -vvv -t install "$DMG" || true
else
    echo "⚠️  未公证（无 Developer ID / NOTARY_PROFILE）；他人首启可能需手动放行"
fi

# 7) 校验
hdiutil verify "$DMG"
echo "==> 完成: ${DMG}"
