# Changelog

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
