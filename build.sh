#!/bin/bash
set -e

EXECUTABLE_NAME="StickyNotes"
APP_NAME="Sticky Notes"
LEGACY_APP_NAME="StickyNotes"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
LEGACY_APP_BUNDLE="$LEGACY_APP_NAME.app"

swift build -c release

rm -rf "$APP_BUNDLE" "$LEGACY_APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "Info.plist" "$APP_BUNDLE/Contents/"

if command -v swift &> /dev/null; then
    swift "$(dirname "$0")/genicon.swift" "$APP_BUNDLE" 2>/dev/null || echo "  (icon generation skipped)"
fi

echo "✅ App bundle created: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
echo "For Spotlight, install with: cp -R \"$APP_BUNDLE\" /Applications/"
