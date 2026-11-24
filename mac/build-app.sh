#!/bin/bash
# Builds NotchBridge.app (release) into mac/build/.
# Usage: ./build-app.sh [--install]   (--install copies it to /Applications and opens it)
#
# Signing: if a code-signing identity named "NotchBridge Local Signing" exists (see make-signing-cert.sh),
# the app is signed with it, so macOS keeps Calendar/Camera/Local Network permissions across rebuilds.
# Otherwise it is ad-hoc signed (works, but macOS may ask for permissions again after each rebuild).
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY_NAME="NotchBridge Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    SIGN="$IDENTITY_NAME"
else
    SIGN="-"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchBridge"

# Now Playing helper (loaded by /usr/bin/perl, see MediaHelper/NowPlayingHelper.m)
mkdir -p .build/helper
clang -dynamiclib -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -O2 \
    -framework Foundation -o .build/helper/libNowPlayingHelper.dylib MediaHelper/NowPlayingHelper.m
codesign --force --sign "$SIGN" .build/helper/libNowPlayingHelper.dylib

# App icon (regenerate with: swift Tools/MakeIcon.swift Resources/AppIcon.icns)
[[ -f Resources/AppIcon.icns ]] || swift Tools/MakeIcon.swift Resources/AppIcon.icns

APP="build/NotchBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchBridge"
cp .build/helper/libNowPlayingHelper.dylib "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN" "$APP"
echo "Built $(pwd)/$APP (signed with: $([[ $SIGN == - ]] && echo ad-hoc || echo "$SIGN"))"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x NotchBridge 2>/dev/null || true
    rm -rf /Applications/NotchBridge.app
    cp -R "$APP" /Applications/
    open /Applications/NotchBridge.app
    echo "Installed to /Applications/NotchBridge.app"
fi
