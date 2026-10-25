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
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>ja</string></array>
    <key>CFBundleName</key><string>MIDITouchPad</string>
    <key>CFBundleDisplayName</key><string>MIDITouchPad</string>
    <key>CFBundleIdentifier</key><string>local.miditouchpad</string>
    <key>CFBundleExecutable</key><string>MIDITouchPad</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.2</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- Dock に出さずメニューバーだけに常駐する -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# 署名。SIGN_IDENTITY に証明書名（例: "Developer ID Application: Your Name (TEAMID)"）を渡すと
# Hardened Runtime 付きで署名する。未指定なら ad-hoc 署名（自分の Mac で動かすだけなら十分）。
# 非公開フレームワークを dlopen するため App Sandbox は使わない。
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP" >/dev/null
fi

echo "built: $APP"
