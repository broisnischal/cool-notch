#!/bin/bash
# Builds CoolNotch and assembles a runnable .app bundle (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP=".build/Cool Notch.app"
BIN=".build/$CONFIG/CoolNotch"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CoolNotch"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundle the Geist fonts (registered at launch by AppFonts).
if [ -d Resources/Fonts ]; then
  mkdir -p "$APP/Contents/Resources/Fonts"
  cp Resources/Fonts/*.ttf Resources/Fonts/*.txt "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
fi

# Bundle the Now Playing adapter (framework + perl bridge + test client).
if [ -d Vendor/mediaremote ]; then
  mkdir -p "$APP/Contents/Resources/mediaremote"
  cp -R Vendor/mediaremote/* "$APP/Contents/Resources/mediaremote/"
fi

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "✓ Built: $APP"
