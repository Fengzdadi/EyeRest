#!/usr/bin/env bash
# Builds build/EyeRest.app from the Swift package, ad-hoc signed for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/EyeRest"

APP=build/EyeRest.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EyeRest"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"
