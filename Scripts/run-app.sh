#!/bin/sh
# Generate the Xcode project, build the app (with rocketd and the rocket CLI inside), and open it.
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

osascript -e 'quit app "Rocket Downloader"' 2>/dev/null || true
while pgrep -x "Rocket Downloader" >/dev/null; do sleep 0.2; done
open ".build/xcode/Build/Products/Debug/Rocket Downloader.app"
