#!/usr/bin/env bash
# Builds build/EyeRest.app from the Swift package, ad-hoc signed for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/EyeRest.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EyeRest" "$BIN_DIR/eyerest-mcp" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Sign the helper first: signing the app seals what's inside it.
codesign --force --sign - "$APP/Contents/MacOS/eyerest-mcp"
codesign --force --sign - "$APP"

echo "Built $APP"
