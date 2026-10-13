#!/bin/bash
# 編譯 arm64 安裝工具並打包成 release 檔案。
#   ./build.sh                 只用現有的 Sources/Embedded.swift 編譯
#   ORIG=<原版Data> NEW=<補丁後Data> VENV=<python venv> ./build.sh regen
#     → 先重新產生內嵌資料（遊戲更新後用）
#   REPO=<GitHub帳號>/dressmaker-zhtw-mac ./build.sh   → 把 install.sh 的下載網址填好
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
mkdir -p build dist

if [ "${1:-}" = regen ]; then
    "$VENV/bin/python" -I tools/make_templates.py "$ORIG" build/templates.json
    "$VENV/bin/python" -I tools/gen_embedded.py "$ORIG" "$NEW" build/templates.json Sources/Embedded.swift
fi

swiftc -O -swift-version 5 -target arm64-apple-macos12.0 \
    -o build/zhtw-patcher Sources/main.swift Sources/Embedded.swift

# app（對話框版）
APP="build/Dressmaker繁中補丁.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/zhtw-patcher "$APP/Contents/MacOS/zhtw-patcher"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>zhtw-patcher</string>
	<key>CFBundleIdentifier</key><string>io.github.dressmaker-zhtw.patcher</string>
	<key>CFBundleName</key><string>Dressmaker繁中補丁</string>
	<key>CFBundleDisplayName</key><string>Dressmaker 繁中補丁</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>12.0</string>
	<key>LSRequiresNativeExecution</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# 簽章：有 Developer ID 就用（可公證），否則 ad-hoc
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none -s "$IDENTITY" build/zhtw-patcher
codesign --force --options runtime --timestamp=none -s "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

# release 檔案
rm -f dist/*
ditto -c -k --keepParent "$APP" "dist/Dressmaker-zhTW-mac-app.zip"
cp build/zhtw-patcher dist/zhtw-patcher-arm64
if [ -n "${REPO:-}" ]; then
    sed "s#__REPO__#$REPO#g" install.sh > dist/install.sh
else
    echo "⚠️  沒有設定 REPO（例如 REPO=帳號/dressmaker-zhtw-mac），install.sh 裡的網址仍是 __REPO__"
    cp install.sh dist/install.sh
fi
( cd dist && shasum -a 256 * > SHA256SUMS.txt )
ls -l dist
