#!/usr/bin/env bash
# release.sh — Build a signed, notarized DMG, generate the Sparkle appcast,
#              create a GitHub Release, and upload the DMG.
#
# Prerequisites (one-time setup):
#   1. Install gh CLI: brew install gh && gh auth login
#   2. Store notarytool credentials:
#        xcrun notarytool store-credentials "notarytool-profile" \
#          --apple-id "your@apple-id.com" \
#          --team-id "PZ44T4KUAK" \
#          --password "app-specific-password"
#
# Usage:
#   ./release.sh [--clobber] <path-to-exported-Gridwell.app>
#
#   --clobber   Overwrite an existing GitHub Release with the same tag.
#               Use when re-releasing the same version (e.g. to replace the DMG).
#
# Workflow:
#   1. Creates and notarizes a DMG from the exported .app
#   2. Runs generate_appcast (signs with your EdDSA key from Keychain)
#   3. Commits the updated appcast.xml to the repo
#   4. Creates a GitHub Release tagged vX.Y and uploads the DMG
#   5. Pushes the appcast.xml commit so the live URL returns the new feed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Configuration ─────────────────────────────────────────────────────────────

GITHUB_REPO="jdeepwell/gridwell"
SIGN_IDENTITY="Developer ID Application"
NOTARYTOOL_PROFILE="notarytool-profile"

SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/$(ls ~/Library/Developer/Xcode/DerivedData | grep '^Gridwell-' | head -1)/SourcePackages/artifacts/sparkle/Sparkle/bin"

# ── Argument parsing ──────────────────────────────────────────────────────────

CLOBBER=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clobber) CLOBBER=true; shift ;;
        *) break ;;
    esac
done

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [--clobber] <path-to-Gridwell.app>"
    exit 1
fi

APP_PATH="$1"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: '$APP_PATH' not found."
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI not found. Install it with: brew install gh"
    exit 1
fi

# ── Derive version from the app bundle ───────────────────────────────────────

PLIST="$APP_PATH/Contents/Info.plist"
[[ ! -f "$PLIST" ]] && PLIST="$APP_PATH/Contents/Resources/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
TAG="v${VERSION}"
DMG_NAME="Gridwell-${VERSION}.dmg"
OUTPUT="$SCRIPT_DIR/releases/${DMG_NAME}"
DOWNLOAD_URL_PREFIX="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/"

echo "==> Releasing Gridwell ${VERSION} (build ${BUILD})"
echo "    Tag:      ${TAG}"
echo "    DMG:      ${DMG_NAME}"
echo "    Download: ${DOWNLOAD_URL_PREFIX}"
$CLOBBER && echo "    Mode:     --clobber (overwriting existing release)"
echo ""

# ── Output directory ──────────────────────────────────────────────────────────

mkdir -p "$SCRIPT_DIR/releases"

# ── Step 1: Re-sign Sparkle components with your Developer ID ─────────────────
# Xcode's export does not re-sign Sparkle's pre-built XPC services and helpers.
# All embedded binaries must be signed with YOUR Developer ID for notarization.
# Sign inside-out: deepest nested components first, main app last.

echo "==> Re-signing Sparkle components…"
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"

codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --preserve-metadata=entitlements,identifier \
    "$SPARKLE_FW/XPCServices/Downloader.xpc"

codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --preserve-metadata=entitlements,identifier \
    "$SPARKLE_FW/XPCServices/Installer.xpc"

codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --preserve-metadata=entitlements,identifier \
    "$SPARKLE_FW/Updater.app"

codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --preserve-metadata=entitlements,identifier \
    "$SPARKLE_FW/Autoupdate"

codesign --force --sign "$SIGN_IDENTITY" --timestamp \
    --preserve-metadata=entitlements,identifier \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework"

# Re-sign the main app last (with Hardened Runtime)
codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    "$APP_PATH"

echo "==> Verifying re-signed app…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# ── Step 2: Create DMG ────────────────────────────────────────────────────────

echo "==> Creating DMG…"
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
    --codesign "$SIGN_IDENTITY" \
    "$OUTPUT" \
    "$APP_PATH"

# ── Step 3: Notarize ──────────────────────────────────────────────────────────

echo "==> Submitting to Apple notarization (this takes a few minutes)…"
xcrun notarytool submit "$OUTPUT" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

# ── Step 4: Staple ────────────────────────────────────────────────────────────

echo "==> Stapling notarization ticket…"
xcrun stapler staple "$OUTPUT"
spctl --assess --type open --context context:primary-signature --verbose "$OUTPUT"

# ── Step 5: Generate appcast ──────────────────────────────────────────────────

echo "==> Generating appcast…"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    "$SCRIPT_DIR/releases/"

# generate_appcast writes appcast.xml into the releases/ folder;
# move it to the repo root so it is served from the raw.githubusercontent.com URL.
mv "$SCRIPT_DIR/releases/appcast.xml" "$SCRIPT_DIR/appcast.xml"

# ── Step 6: Commit appcast.xml ────────────────────────────────────────────────

echo "==> Committing appcast.xml…"
git add appcast.xml
git commit -m "release: update appcast for v${VERSION}"

# ── Step 7: Create GitHub Release and upload DMG ─────────────────────────────

echo "==> Creating GitHub Release ${TAG}…"
if $CLOBBER; then
    gh release delete "$TAG" --repo "$GITHUB_REPO" --yes --cleanup-tag=false 2>/dev/null || true
fi

gh release create "$TAG" \
    "$OUTPUT" \
    --repo "$GITHUB_REPO" \
    --title "Gridwell ${VERSION}" \
    --notes "See [CHANGELOG](https://github.com/${GITHUB_REPO}/blob/main/CHANGELOG.md) for details."

# ── Step 8: Push appcast.xml ──────────────────────────────────────────────────

echo "==> Pushing appcast.xml…"
git push

echo ""
echo "✓ Done!"
echo "    DMG:     https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${DMG_NAME}"
echo "    Appcast: https://raw.githubusercontent.com/${GITHUB_REPO}/main/appcast.xml"
