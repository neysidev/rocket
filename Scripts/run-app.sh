#!/bin/sh
# Generate the Xcode project, build the app (with rocketd and the rocket CLI inside), load the agent, and open the app.
set -e
cd "$(dirname "$0")/.."

# Use full Xcode even if xcode-select points at the Command Line Tools.
if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

xcodebuild -project Rocket.xcodeproj -scheme Rocket -configuration Debug \
    -derivedDataPath .build/xcode -quiet build

APP="$PWD/.build/xcode/Build/Products/Debug/Rocket Downloader.app"
LABEL="io.github.neysidev.rocket.agent"
DOMAIN="gui/$(id -u)"

osascript -e 'quit app "Rocket Downloader"' 2>/dev/null || true
while pgrep -x "Rocket Downloader" >/dev/null; do sleep 0.2; done

# Debug builds load the agent straight into launchd. Release builds register it with SMAppService, which pins the
# agent's code signature; ad-hoc Debug signatures change on every build, so launchd would refuse the new rocketd.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
PLIST="$PWD/.build/xcode/$LABEL.plist"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>Program</key><string>$APP/Contents/MacOS/rocketd</string>
  <key>MachServices</key><dict><key>$LABEL</key><true/></dict>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
launchctl bootstrap "$DOMAIN" "$PLIST"

open "$APP"
