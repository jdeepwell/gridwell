# Changelog

## [1.0.3] - 2026-04-20

### Added
- **Check for Updates button** — the Updates preferences tab now has a "Check for Updates…" button alongside the automatic-check toggle, so you can trigger a check without going to the menu bar.

### Fixed
- **Sparkle windows now open in front** — the update window and "You're up to date" alert now reliably appear in front when triggered from the menu bar or the preferences window, consistent with the fix already applied to the settings window.

## [1.0.2] - 2026-04-20

### Added
- **Configurable trigger shortcut** — the drag trigger is no longer limited to a single modifier key. Record any combination of modifiers and optionally a regular key (e.g. ⌃⌥F) in the Keys preferences tab. Non-modifier trigger keys are fully suppressed so they do not reach other applications.

### Improved
- **Drag and resize work when Gridwell is the active app** — interactions now work regardless of which app is frontmost, including when the Gridwell settings window is open.
- **Four-edge window snapping** — when snap-to-windows is active, all four edges of the moved window snap to nearby window edges; the nearest edge wins.
- **Versioned settings migrations** — UserDefaults keys are now plain names; existing settings are migrated automatically on first launch.

## [1.0.1] - 2026-04-15

### Added
- **Updates preferences tab** — toggle automatic update checks at any time; reflects the choice made at first launch.

### Improved
- **Resize from all four edges** — left and top edges now trigger resize (outer 25 % of the window), in addition to the existing right and bottom edges. Corners activate both adjacent edges simultaneously.
- **Smarter grid snap height** — cursor position within a row now determines window height: top half of a row snaps to one cell, bottom half spans two rows. On grids with more than two rows, dragging very close to the bottom of the screen snaps to full screen height.
- **Settings window always opens in front** — the preferences window now reliably appears above other windows when opened from the menu bar.

### Fixed
- Sparkle no longer logs a background-update warning on launch; background updates now show a subtle "Update Available…" menu item instead of a hidden alert.

## [1.0] - 2026-04-15

### Added
- Initial release of Gridwell, a macOS window management utility
- Drag windows anywhere (not just the title bar) by holding a configurable modifier key
- Snap windows to a customizable grid or to the edges of other windows
- Per-screen grid configuration with live preview
- Configurable modifier keys for drag trigger, snap-to-grid, and snap-to-windows
- Runs as a menu bar agent with no Dock icon
- Automatic updates via Sparkle
