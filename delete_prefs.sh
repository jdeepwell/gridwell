#!/bin/zsh
# Deletes all of Gridwell's preferences so the app starts fresh on next launch
# (default settings, first-launch update prompt, current settings version).
#
# Usage:
#   ./delete_prefs.sh                  # delete preferences
#   ./delete_prefs.sh --accessibility  # also reset the Accessibility permission,
#                                      # so the first-launch permission flow runs again
#
# A timestamped backup of the current preferences is written to PrefsBackups/ first.
# Restore it with: ./reset_prefs_to_v3.sh --restore PrefsBackups/<file>.plist
# Gridwell is quit if it is running.

set -euo pipefail

DOMAIN="at.deepwell.Gridwell"
PLIST="$HOME/Library/Preferences/$DOMAIN.plist"
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/PrefsBackups"

RESET_ACCESSIBILITY=false
case "${1:-}" in
    "") ;;
    --accessibility) RESET_ACCESSIBILITY=true ;;
    *) echo "Usage: $0 [--accessibility]"; exit 1 ;;
esac

pkill -x Gridwell 2>/dev/null && sleep 1 || true

if [[ -f "$PLIST" ]]; then
    mkdir -p "$BACKUP_DIR"
    BACKUP="$BACKUP_DIR/$DOMAIN-$(date +%Y%m%d-%H%M%S).plist"
    cp "$PLIST" "$BACKUP"
    echo "Backup: $BACKUP"

    # Delete via the full path: a leftover sandbox container for this bundle ID would
    # otherwise make `defaults` operate on the container's (unused) preferences instead.
    defaults delete "$PLIST"
    echo "Preferences deleted."
else
    echo "No preferences found at $PLIST — nothing to delete."
fi

if $RESET_ACCESSIBILITY; then
    tccutil reset Accessibility "$DOMAIN"
    echo "Accessibility permission reset."
fi

echo "Start Gridwell to begin with default settings."
