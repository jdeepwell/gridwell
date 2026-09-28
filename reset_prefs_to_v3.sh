#!/bin/zsh
# Resets Gridwell's preferences to the settings version 3 format (single snap keys)
# so the v3 → v4 migration (modifier combinations) can be tested again.
#
# Usage:
#   ./reset_prefs_to_v3.sh [windowSnapKey] [appWindowSnapKey] [gridSnapKey]
#   Keys: fn | shift | control | option | command   (defaults: shift option control)
#
#   ./reset_prefs_to_v3.sh --restore <backup.plist>
#   Restores a backup made by this script (or any copy of the plist).
#
# A timestamped backup of the current preferences is written to PrefsBackups/ first.
# Quit Gridwell before running; the script quits it if it is still running.

set -euo pipefail

DOMAIN="at.deepwell.Gridwell"
PLIST="$HOME/Library/Preferences/$DOMAIN.plist"
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/PrefsBackups"

pkill -x Gridwell 2>/dev/null && sleep 1 || true

if [[ "${1:-}" == "--restore" ]]; then
    [[ -f "${2:-}" ]] || { echo "Usage: $0 --restore <backup.plist>"; exit 1; }
    cp "$2" "$PLIST"
    killall cfprefsd 2>/dev/null || true   # drop the cached copy so the file is re-read
    echo "Restored $2"
    exit 0
fi

mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/$DOMAIN-$(date +%Y%m%d-%H%M%S).plist"
cp "$PLIST" "$BACKUP"
echo "Backup: $BACKUP"

defaults write "$PLIST" settingsVersion  -int    3
defaults write "$PLIST" windowSnapKey    -string "${1:-shift}"
defaults write "$PLIST" appWindowSnapKey -string "${2:-option}"
defaults write "$PLIST" gridSnapKey      -string "${3:-control}"
for key in windowSnapModifiers appWindowSnapModifiers gridSnapModifiers edgeShrinkModifiers; do
    defaults delete "$PLIST" "$key" 2>/dev/null || true
done

echo "Preferences reset to v3: windowSnapKey=${1:-shift} appWindowSnapKey=${2:-option} gridSnapKey=${3:-control}"
echo "The drag trigger is left unchanged. Start Gridwell to run the migration."
