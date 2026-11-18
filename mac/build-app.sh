#!/bin/bash
# Builds NotchBridge.app (release, ad-hoc signed) into mac/build/.
# Usage: ./build-app.sh [--install]   (--install copies it to /Applications and opens it)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchBridge"

APP="build/NotchBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchBridge"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x NotchBridge 2>/dev/null || true
    rm -rf /Applications/NotchBridge.app
    cp -R "$APP" /Applications/
    open /Applications/NotchBridge.app
    echo "Installed to /Applications/NotchBridge.app"
fi
