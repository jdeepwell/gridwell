# Changelog

## [1.0.10] - 2026-05-30

### Improved
- **Grid preview fills card width** — the grid preview in the Grid preferences tab now expands to fill the available width of its card, giving equal padding on all four sides. Ultra-wide monitors (e.g. 5120 × 2160) now show the full-width grid instead of a small centered rectangle with large empty margins.

## [1.0.9] - 2026-05-30

### Fixed
- **Sparkle "Ready to Install" panel now opens in front** — when Sparkle transitions from the download progress window to the "Install and Relaunch" panel, the new window now reliably appears in front of other apps instead of opening in the background.

## [1.0.8] - 2026-05-30

### Added
- **Mouse button app exceptions** — define a list of apps where the mouse button trigger is disabled, so the button's native behaviour (e.g. middle-click auto-scroll in browsers) is preserved. Configurable via a new "Mouse Button Exceptions" card in the Keys preferences tab: click + to pick an app, − to remove it.

## [1.0.7] - 2026-05-30

### Added
- **Mouse button trigger** — drag and resize windows using a dedicated extra mouse button (middle, back, forward, etc.) without holding any modifier key. Configure it via a click-to-record row in the Keys preferences tab. The keyboard shortcut trigger continues to work independently.
- **Percentage-based resize border** — the resize border is now defined as a percentage of the window dimension (1–50 %, default 25 %) plus a minimum pixel floor (0–300 pt, default 40 pt). The effective border is `max(dimension × %, minimum px)`.

### Improved
- **Custom menu bar icon** — the menu bar now shows a custom Gridwell icon instead of a generic SF Symbol.

## [1.0.6] - 2026-05-05

### Improved
- **Settings refresh** — the Grid, Behaviour, and Keys preferences tabs now use a cleaner card-based layout with clearer hierarchy and spacing.
- **Behaviour controls** — minimum window size and resize-border width now use sliders with large numeric readouts instead of compact steppers.
- **Grid configuration** — column and row counts now use discrete sliders, and the grid preview has stronger contrast and clearer cell boundaries.
- **Release metadata reliability** — Xcode project version metadata, Info.plist values, and release automation now share the same source of truth so future releases keep Xcode and the published app version in sync.

## [1.0.5] - 2026-05-04

### Added
- **Configurable resize border width** — the width of the edge zone that triggers a resize (default 150 pt) is now configurable in the Behaviour preferences tab. Raise or lower it to suit your workflow.
- **Minimum window size filter** — small accessory windows (palette views, attached panels) below a configurable minimum width or height are now excluded from drag and resize. Defaults to 100 × 100 pt; configurable in the Behaviour tab. Set either value to 0 to disable filtering for that dimension.
- **Per-app window snapping** — a new snap modifier (default: Option) snaps only to windows of the same application. The existing window-snap modifier (Shift) continues to snap to all on-screen windows. Both are configurable in the Keys tab.

## [1.0.4] - 2026-04-20

### Added
- **First-launch onboarding** — after granting Accessibility permission, the waiting window transitions to a "You're All Set!" screen that shows where to find Gridwell in the menu bar. Dismisses automatically after 8 seconds or on "Got it".

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
