#!/bin/bash
# Builds build/Vigil.app (needs only the Xcode Command Line Tools).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Vigil.app"

swift build -c release --package-path "$ROOT/app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/app/.build/release/Vigil" "$APP/Contents/MacOS/"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Vigil</string>
  <key>CFBundleIdentifier</key><string>com.roussev.vigil</string>
  <key>CFBundleExecutable</key><string>Vigil</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.9.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP" >/dev/null
echo "Built $APP"
