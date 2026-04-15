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
#   ./release.sh <path-to-exported-Gridwell.app>
#
# Example:
#   ./release.sh ~/Desktop/Gridwell.app
#
# Workflow:
#   1. Creates and notarizes a DMG from the exported .app
#   2. Runs generate_appcast (signs with your EdDSA key from Keychain)
#   3. Commits the updated appcast.xml to the repo
#   4. Creates a GitHub Release tagged vX.Y and uploads the DMG
#   5. Pushes the appcast.xml commit so the live URL returns the new feed

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

GITHUB_REPO="jdeepwell/gridwell"
SIGN_IDENTITY="Developer ID Application"
NOTARYTOOL_PROFILE="notarytool-profile"

SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/$(ls ~/Library/Developer/Xcode/DerivedData | grep '^Gridwell-' | head -1)/SourcePackages/artifacts/sparkle/Sparkle/bin"

# ── Input validation ──────────────────────────────────────────────────────────

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-Gridwell.app>"
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
if [[ ! -f "$PLIST" ]]; then
    PLIST="$APP_PATH/Contents/Resources/Info.plist"
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
TAG="v${VERSION}"
DMG_NAME="Gridwell-${VERSION}.dmg"
DOWNLOAD_URL_PREFIX="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/"

echo "==> Releasing Gridwell ${VERSION} (build ${BUILD})"
echo "    Tag:      ${TAG}"
echo "    DMG:      ${DMG_NAME}"
echo "    Download: ${DOWNLOAD_URL_PREFIX}"
echo ""

# ── Output directory ──────────────────────────────────────────────────────────

mkdir -p releases

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
hdiutil create \
    -volname "Gridwell ${VERSION}" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "releases/${DMG_NAME}"

# ── Step 3: Sign the DMG ──────────────────────────────────────────────────────

echo "==> Signing DMG…"
codesign \
    --sign "$SIGN_IDENTITY" \
    --timestamp \
    "releases/${DMG_NAME}"

codesign --verify --verbose "releases/${DMG_NAME}"

# ── Step 4: Notarize ──────────────────────────────────────────────────────────

echo "==> Submitting to Apple notarization (this takes a few minutes)…"
xcrun notarytool submit "releases/${DMG_NAME}" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

# ── Step 5: Staple ────────────────────────────────────────────────────────────

echo "==> Stapling notarization ticket…"
xcrun stapler staple "releases/${DMG_NAME}"
spctl --assess --type open --context context:primary-signature --verbose "releases/${DMG_NAME}"

# ── Step 6: Generate appcast ──────────────────────────────────────────────────

echo "==> Generating appcast…"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    releases/

# generate_appcast writes appcast.xml into the releases/ folder;
# move it to the repo root so it is served from the raw.githubusercontent.com URL.
mv releases/appcast.xml ./appcast.xml

# ── Step 7: Commit appcast.xml ────────────────────────────────────────────────

echo "==> Committing appcast.xml…"
git add appcast.xml
git commit -m "release: update appcast for v${VERSION}"

# ── Step 8: Create GitHub Release and upload DMG ─────────────────────────────

echo "==> Creating GitHub Release ${TAG}…"
gh release create "$TAG" \
    "releases/${DMG_NAME}" \
    --repo "$GITHUB_REPO" \
    --title "Gridwell ${VERSION}" \
    --notes "See [CHANGELOG](CHANGELOG.md) for details."

# ── Step 9: Push appcast.xml ──────────────────────────────────────────────────

echo "==> Pushing appcast.xml…"
git push

echo ""
echo "✓ Done!"
echo "    DMG:     https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${DMG_NAME}"
echo "    Appcast: https://raw.githubusercontent.com/${GITHUB_REPO}/main/appcast.xml"
