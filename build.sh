#!/bin/bash
set -e

APP_NAME="StickyNotes"
BUILD_DIR=".build/release"

swift build -c release

rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_NAME.app/Contents/MacOS/"
cp "Info.plist" "$APP_NAME.app/Contents/"

if command -v swift &> /dev/null; then
    swift "$(dirname "$0")/genicon.swift" 2>/dev/null || echo "  (icon generation skipped)"
fi

echo "✅ App bundle created: $APP_NAME.app"
echo "Run with: open $APP_NAME.app"
