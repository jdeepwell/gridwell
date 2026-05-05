#!/usr/bin/env bash
# bump_version.sh — Update MARKETING_VERSION and CURRENT_PROJECT_VERSION
# in the Xcode project.
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

usage() {
    cat <<'EOF'
Usage:
  ./bump_version.sh [<new-version>]

If <new-version> is omitted, the patch component is incremented by 1.
The build number is always set to YYYYMMDDss, where ss is a two-digit
serial for today.
EOF
}

if [[ $# -gt 1 ]]; then
    usage
    exit 1
fi

if [[ $# -eq 1 ]]; then
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Error: unknown option '$1'." >&2
            usage >&2
            exit 1
            ;;
    esac
fi

# ── Read current values ───────────────────────────────────────────────────────

CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *$//')
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *$//')

if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: current MARKETING_VERSION '$CURRENT_VERSION' is not in X.Y.Z format." >&2
    exit 1
fi

echo "Current version: $CURRENT_VERSION"
echo "Current build:   $CURRENT_BUILD"

# ── Determine new marketing version ──────────────────────────────────────────

if [[ $# -ge 1 ]]; then
    NEW_VERSION="$1"
    if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: new version '$NEW_VERSION' is not in X.Y.Z format." >&2
        exit 1
    fi
else
    IFS='.' read -r major minor patch <<< "$CURRENT_VERSION"
    patch=$(( ${patch:-0} + 1 ))
    NEW_VERSION="${major}.${minor}.${patch}"
fi

# ── Determine new build number ────────────────────────────────────────────────

TODAY=$(date +%Y%m%d)
CURRENT_DATE_PART="${CURRENT_BUILD:0:8}"

if [[ "$CURRENT_BUILD" =~ ^[0-9]{10}$ && "$CURRENT_DATE_PART" == "$TODAY" ]]; then
    CURRENT_SERIAL="${CURRENT_BUILD:8:2}"
    NEW_SERIAL=$(printf "%02d" $(( 10#$CURRENT_SERIAL + 1 )))
else
    NEW_SERIAL="01"
fi

NEW_BUILD="${TODAY}${NEW_SERIAL}"

echo "New version:     $NEW_VERSION"
echo "New build:       $NEW_BUILD"

# ── Apply ─────────────────────────────────────────────────────────────────────

export NEW_VERSION NEW_BUILD
perl -0pi -e 's/(MARKETING_VERSION = )[^;]+;/${1}$ENV{NEW_VERSION};/g' "$PBXPROJ"
perl -0pi -e 's/(CURRENT_PROJECT_VERSION = )[^;]+;/${1}$ENV{NEW_BUILD};/g' "$PBXPROJ"

# Keep the source Info.plist tied to the Xcode build settings so Xcode's
# General tab and the built app bundle cannot drift apart.
plutil -replace CFBundleShortVersionString -string '$(MARKETING_VERSION)' "$SCRIPT_DIR/Info.plist"
plutil -replace CFBundleVersion -string '$(CURRENT_PROJECT_VERSION)' "$SCRIPT_DIR/Info.plist"

echo "✓ Version bumped to ${NEW_VERSION} (build ${NEW_BUILD})."
