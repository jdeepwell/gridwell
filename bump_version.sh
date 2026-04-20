#!/usr/bin/env bash
# bump_version.sh — Update MARKETING_VERSION and CURRENT_PROJECT_VERSION
# in the Xcode project using agvtool.
#
# Usage:
#   ./bump_version.sh [<new-version>]
#
#   If <new-version> is omitted, the patch component is incremented by 1.
#
# Build number scheme: YYYYMMDDss
#   - YYYYMMDD = today's date
#   - ss       = two-digit serial starting at 01
#   If the current build number already uses today's date, the serial is
#   incremented rather than reset to 01.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PBXPROJ="$SCRIPT_DIR/Gridwell.xcodeproj/project.pbxproj"

# ── Read current values ───────────────────────────────────────────────────────

CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *$//')
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *$//')

echo "Current version: $CURRENT_VERSION"
echo "Current build:   $CURRENT_BUILD"

# ── Determine new marketing version ──────────────────────────────────────────

if [[ $# -ge 1 ]]; then
    NEW_VERSION="$1"
else
    IFS='.' read -r major minor patch <<< "$CURRENT_VERSION"
    patch=$(( ${patch:-0} + 1 ))
    NEW_VERSION="${major}.${minor}.${patch}"
fi

# ── Determine new build number ────────────────────────────────────────────────

TODAY=$(date +%Y%m%d)
CURRENT_DATE_PART="${CURRENT_BUILD:0:8}"

if [[ "$CURRENT_DATE_PART" == "$TODAY" ]]; then
    CURRENT_SERIAL="${CURRENT_BUILD:8:2}"
    NEW_SERIAL=$(printf "%02d" $(( 10#$CURRENT_SERIAL + 1 )))
else
    NEW_SERIAL="01"
fi

NEW_BUILD="${TODAY}${NEW_SERIAL}"

echo "New version:     $NEW_VERSION"
echo "New build:       $NEW_BUILD"

# ── Apply via agvtool ─────────────────────────────────────────────────────────

cd "$SCRIPT_DIR"
xcrun agvtool new-marketing-version "$NEW_VERSION" > /dev/null
xcrun agvtool new-version -all "$NEW_BUILD" > /dev/null

echo "✓ Version bumped to ${NEW_VERSION} (build ${NEW_BUILD})."
