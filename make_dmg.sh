#!/usr/bin/env bash
# make_dmg.sh — Creates a styled DMG using create-dmg for testing.
#               No signing, notarization, or GitHub upload.
#
# Usage:
#   ./make_dmg.sh <path-to-Gridwell.app>
#
# Example:
#   ./make_dmg.sh ~/Desktop/Gridwell.app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-Gridwell.app>"
    exit 1
fi

APP_PATH="$1"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: '$APP_PATH' not found."
    exit 1
fi

PLIST="$APP_PATH/Contents/Info.plist"
[[ ! -f "$PLIST" ]] && PLIST="$APP_PATH/Contents/Resources/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
DMG_NAME="Gridwell-${VERSION}-test.dmg"
OUTPUT="$SCRIPT_DIR/releases/${DMG_NAME}"

echo "==> Building test DMG for Gridwell ${VERSION}…"

mkdir -p "$SCRIPT_DIR/releases"

# Remove stale output so create-dmg doesn't prompt
[[ -f "$OUTPUT" ]] && rm "$OUTPUT"

create-dmg \
    --volname "Gridwell ${VERSION}" \
    --background "$SCRIPT_DIR/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 576 464 \
    --icon-size 100 \
    --text-size 13 \
    --icon "Gridwell.app" 160 180 \
    --hide-extension "Gridwell.app" \
    --app-drop-link 416 180 \
    "$OUTPUT" \
    "$APP_PATH"

echo ""
echo "✓ Done: releases/${DMG_NAME}"
open "$OUTPUT"
