#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ArenaBridge"
BUNDLE_ID="dev.arena.bridge"
VERSION="1.0"

echo "==> 编译 Swift 包（release）"
swift build -c release

BIN=".build/release/${APP_NAME}"
APP="build/${APP_NAME}.app"

echo "==> 组装 App Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"

if [ ! -f build/AppIcon.icns ]; then
  echo "==> 生成图标"
  mkdir -p build/icon.iconset
  swift make_icon.swift build/icon_1024.png
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" build/icon_1024.png --out "build/icon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" build/icon_1024.png --out "build/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns build/icon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>ArenaBridge</string>
</dict>
</plist>
PLIST

echo "==> 签名（ad-hoc）"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "（签名跳过）"

echo "==> 完成：$APP"
