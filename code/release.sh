#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

MODE="${1:-publish}"
if [[ "$MODE" != "publish" && "$MODE" != "--dmg-only" ]]; then
  echo "用法：./release.sh [--dmg-only]" >&2
  exit 1
fi

VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION: "?([^\"]+)"?$/\1/p' project.yml | head -1)"
APP="$PWD/build/Build/Products/Release/IPA Tool.app"
DMG="$PWD/build/ipatool.For.Mac.dmg"
STAGING="$PWD/build/release-staging"
NOTES="$PWD/release-notes/$VERSION.md"

[[ -n "$VERSION" ]] || { echo "读取版本号失败" >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "缺少发布说明：$NOTES" >&2; exit 1; }

if [[ "$MODE" == "publish" ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "请先提交当前改动" >&2; exit 1; }
  [[ "$(git rev-list -n 1 "$VERSION" 2>/dev/null)" == "$(git rev-parse HEAD)" ]] || {
    echo "请先给当前提交打上 $VERSION tag" >&2
    exit 1
  }
  command -v gh >/dev/null || { echo "请先安装 GitHub CLI" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "请先运行 gh auth login" >&2; exit 1; }
fi

cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

xcodegen generate
xcodebuild -quiet -project IpaToolMac.xcodeproj -scheme IpaToolMac \
  -configuration Release -derivedDataPath build -destination 'platform=macOS' clean build

[[ -d "$APP" ]] || { echo "没有找到 Release App" >&2; exit 1; }
[[ ! -e "$APP/Contents/Helpers/ipatool" ]] || { echo "App 中仍包含 ipatool" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/IPA Tool.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "IPA Tool $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG"
hdiutil verify -quiet "$DMG"

if [[ "$MODE" == "publish" ]]; then
  gh release create "$VERSION" "$DMG" --verify-tag --latest \
    --title "IPA Tool for Mac $VERSION" --notes-file "$NOTES"
fi

echo "完成：$DMG"
shasum -a 256 "$DMG"
