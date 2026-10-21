#!/bin/bash
# MIDITouchPad.app を build/ に生成する。
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
APP="build/MIDITouchPad.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MIDITouchPad"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MIDITouchPad"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MIDITouchPad</string>
    <key>CFBundleDisplayName</key><string>MIDITouchPad</string>
    <key>CFBundleIdentifier</key><string>local.miditouchpad</string>
    <key>CFBundleExecutable</key><string>MIDITouchPad</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- Dock に出さずメニューバーだけに常駐する -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# 非公開フレームワークを dlopen するため、署名は ad-hoc（sandbox 無し）にする
codesign --force --sign - "$APP" >/dev/null

echo "built: $APP"
