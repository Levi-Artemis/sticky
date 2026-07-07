#!/bin/bash
set -euo pipefail

APP_NAME="Sticky Notes"
EXECUTABLE_NAME="StickyNotes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_APP="$SCRIPT_DIR/$APP_NAME.app"
DEST_APP="${1:-/Applications/$APP_NAME.app}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if ! command -v swift >/dev/null 2>&1; then
    echo "Error: swift was not found. Install Xcode Command Line Tools first:"
    echo "  xcode-select --install"
    exit 1
fi

case "$DEST_APP" in
    */"$APP_NAME.app") ;;
    *)
        echo "Error: refusing to install to an unexpected path:"
        echo "  $DEST_APP"
        echo "Destination must end with: $APP_NAME.app"
        exit 1
        ;;
esac

cd "$SCRIPT_DIR"
bash "$SCRIPT_DIR/build.sh"

if [[ ! -x "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
    echo "Error: built app executable was not found:"
    echo "  $SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME"
    exit 1
fi

DEST_PARENT="$(dirname "$DEST_APP")"
if [[ ! -d "$DEST_PARENT" ]]; then
    echo "Creating destination directory: $DEST_PARENT"
    if [[ -w "$(dirname "$DEST_PARENT")" ]]; then
        mkdir -p "$DEST_PARENT"
    else
        sudo mkdir -p "$DEST_PARENT"
    fi
fi

if pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
    echo "Note: $APP_NAME appears to be running. Quit and reopen it after install."
fi

echo "Installing to: $DEST_APP"
if [[ -w "$DEST_PARENT" ]]; then
    rm -rf "$DEST_APP"
    ditto "$SOURCE_APP" "$DEST_APP"
else
    sudo rm -rf "$DEST_APP"
    sudo ditto "$SOURCE_APP" "$DEST_APP"
fi

if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DEST_APP" || true
fi

BUILT_SIZE="$(stat -f%z "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME")"
INSTALLED_SIZE="$(stat -f%z "$DEST_APP/Contents/MacOS/$EXECUTABLE_NAME")"

echo "Built executable:     $BUILT_SIZE bytes"
echo "Installed executable: $INSTALLED_SIZE bytes"
echo "Done. Open with:"
echo "  open \"$DEST_APP\""
