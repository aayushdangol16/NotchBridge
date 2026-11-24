#!/bin/bash
# Builds NotchBridge.app (release, ad-hoc signed) into mac/build/.
# Usage: ./build-app.sh [--install]   (--install copies it to /Applications and opens it)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchBridge"

# Now Playing helper (loaded by /usr/bin/perl, see MediaHelper/NowPlayingHelper.m)
mkdir -p .build/helper
clang -dynamiclib -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -O2 \
    -framework Foundation -o .build/helper/libNowPlayingHelper.dylib MediaHelper/NowPlayingHelper.m
codesign --force --sign - .build/helper/libNowPlayingHelper.dylib

APP="build/NotchBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchBridge"
cp .build/helper/libNowPlayingHelper.dylib "$APP/Contents/Resources/"
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
