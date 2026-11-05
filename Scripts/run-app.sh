#!/bin/sh
# Build the app with SwiftPM, wrap it in a minimal .app bundle, and open it.
set -e
cd "$(dirname "$0")/.."
swift build --product Rocket
APP=".build/Rocket Downloader.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/Rocket "$APP/Contents/MacOS/Rocket"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.neysidev.rocket</string>
  <key>CFBundleName</key><string>Rocket</string>
  <key>CFBundleExecutable</key><string>Rocket</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
open "$APP"
