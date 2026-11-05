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

APP=".build/xcode/Build/Products/Debug/Rocket Downloader.app"
AGENT="gui/$(id -u)/io.github.neysidev.rocket.agent"
BEFORE=$(cksum "$APP/Contents/MacOS/rocketd" 2>/dev/null || true)

xcodebuild -project Rocket.xcodeproj -scheme Rocket -configuration Debug \
    -derivedDataPath .build/xcode -quiet build

quit_app() {
    osascript -e 'quit app "Rocket Downloader"' 2>/dev/null || true
    while pgrep -x "Rocket Downloader" >/dev/null; do sleep 0.2; done
}

quit_app
launchctl bootout "$AGENT" 2>/dev/null || true

# Registering the agent pins its code signature (cdhash). Ad-hoc builds get a new one on every build, and
# launchd refuses the new rocketd until the app has registered that build once and the job is reloaded.
# So when the agent changed: launch once to register it, then reload the job. Signed builds won't need this.
if [ "$BEFORE" != "$(cksum "$APP/Contents/MacOS/rocketd")" ]; then
    open "$APP"
    for _ in $(seq 50); do launchctl print "$AGENT" >/dev/null 2>&1 && break; sleep 0.2; done
    quit_app
    launchctl bootout "$AGENT" 2>/dev/null || true
fi

open "$APP"
