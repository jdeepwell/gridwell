We are building a macOS utility application.

The purpose of this application is window management.

The user should be able to grab windows, not only in the title bar, but anywhere in the window, while holding configurable modifier keys.

When dragging near a border, the window should be resized. When dragging near the middle, the window should be moved.

The user should be able to define a personalized grid.

When the windows are resized or moved, they should snap to this grid, or to the edges of other windows - whichever is nearer.

You are provided with the basic application template from Xcode. 

## Current Status

**Completed: Stages 1, 2, 3, 4, 5, 6, menu bar conversion, deployment/distribution, post-1.0 refinements, post-1.0.1 feature additions, post-1.0.2 improvements, post-1.0.3 refinements, and first-launch onboarding. Current release: v1.0.3.**

### Architecture
- `GridwellApp.swift` — `MenuBarExtra` + `Settings` scenes only. App runs as a menu bar agent (`LSUIElement = YES`): no Dock icon, no App Switcher entry. Menu bar icon uses SF Symbol `rectangle.3.group`. Menu contains: Settings… (⌘,), Update Available… (conditional), Check for Updates…, About Gridwell, Quit Gridwell (⌘Q). Settings window is opened via the private `SettingsButton` view that captures `@Environment(\.openSettings)` — the correct SwiftUI API (macOS 14+); using the deprecated `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)` selector produces a runtime warning and must be avoided. `SparkleManager` owns the `SPUStandardUpdaterController` and implements `SPUStandardUserDriverDelegate` for gentle background-update reminders. Settings scene injects `GridConfigStore.shared` and `SparkleManager` as environment objects.
- `AppDelegate.swift` — Requests Accessibility permission on launch (shows alert + opens System Settings if not granted). Starts monitors once trusted. Observes `NSWindow.willCloseNotification` to revert the app to `.accessory` activation policy when the last key window closes.
- `ModifierKeyMonitor.swift` — Pure state store for trigger detection. Tracks current modifier flags and non-modifier key state. Exposes `handleFlagsChanged(_:CGEvent)`, `handleKeyDown(keyCode:)`, `handleKeyUp(keyCode:)` — called directly by the CGEventTap in `MouseInteractionHandler`. Computes `isTriggerActive` from both modifier and key state against the configured `TriggerShortcut`.
- `MouseInteractionHandler.swift` — Single `CGEventTap` at `.cgSessionEventTap` / `.headInsertEventTap` covering **all** intercepted event types: `leftMouseDown/Dragged/Up` (drag/resize), `flagsChanged` (modifier tracking, always passed through), `keyDown/keyUp` (key tracking; suppressed if they match the trigger shortcut). This single session-level tap covers both app-active and app-inactive cases. Identifies the target window via `WindowInfoProvider`. Computes candidate frames via `GridSnapper` and forwards them to `WindowManipulator`.
- `WindowInfoProvider.swift` — Uses `CGWindowListCopyWindowInfo` to enumerate on-screen windows. Exposes `window(at: CGPoint)` for hit-testing in CoreGraphics coordinates. `WindowInfo` includes `pid` for use by the Accessibility API. When multiple windows overlap the click point, `window(at:)` re-queries the window server for a fresh front-to-back ordering (since `CGWindowListCopyWindowInfo` does not guarantee order within the same layer) and returns the genuinely topmost candidate. Phantom/ghost windows are excluded via four combined guards: `layer == 0` (drops menu bar items and system overlays), `alpha > 0` (drops transparent utility surfaces), a system-owner blocklist (`Window Server`, `Dock`, `SystemUIServer`, `Control Center`, etc.), and non-zero frame size.
- `WindowManipulator.swift` — Uses `AXUIElementCreateApplication(pid)` + `kAXPositionAttribute`/`kAXSizeAttribute` to move and resize windows via the Accessibility API. When the target window belongs to Gridwell's own process, uses `NSWindow.setFrame` (AppKit) instead — the AX API cannot manipulate the calling app's own windows. A `DispatchSourceTimer` (10 Hz) on a background serial queue applies the latest pending frame. Each frame is applied via a `setFrame` helper that sets **size before position** (to prevent the system from repositioning the window after a size change) and uses a **read-back retry loop** (up to 5 attempts) that verifies **both position and size** before declaring success. `AXEnhancedUserInterface` is intentionally never touched, as disabling it causes VoiceOver regressions and Chromium UI freezes. `raiseWindow(pid:)` brings the target window and its app to the front at drag start.
- `GridConfigStore.swift` — `ObservableObject` singleton. Stores a `[String: ScreenGridConfig]` (columns + rows per screen), `raiseWindowOnDrag: Bool`, a `TriggerShortcut` (JSON-encoded), and two `ModifierKey` snap keys in `UserDefaults`. Screen keys use point-space dimensions only (e.g. `"2560x1440"`), falling back to appending origin when two screens share the same size. Uses a versioned migration system: a `settingsVersion` integer in `UserDefaults` tracks the current data structure version; on init, `runMigrations()` runs all pending migrations in sequence. Current version: 2. Migration v0→v1 converts the legacy single-`ModifierKey` trigger to `TriggerShortcut`; migration v1→v2 renames all `com.gridwell.*` keys to plain names.
- `GridSnapper.swift` — Stateless helpers for drag-zone detection, candidate frame computation, and snapping. Contains `SnapMode` enum (`.none`, `.windows`, `.grid`). When moving with window-snap active, snaps whichever of the window's four edges (left, right, top, bottom) is nearest to a candidate edge — not just left/top. Screen detection for snapping uses the **cursor position** (not the candidate window frame) via `containingScreen(for: CGPoint)`. The `cgFrame` helper converts NSScreen → CG coordinates using `NSScreen.screens.first` (the stable primary display) for the Y-flip height.
- `ModifierKey.swift` — `ModifierKey` enum (`.fn`, `.shift`, `.control`, `.option`, `.command`) for snap modifier keys. Also contains `TriggerShortcut` struct: `Codable`/`Equatable`, holds `modifierFlagsRaw: UInt` + optional `keyCode: UInt16` + optional `keyDisplayString: String`. Includes `displayString` (e.g. "fn", "⌃⌥F"), `relevantModifiers` constant, and `defaultFN` singleton.
- `PreferencesView.swift` — Tabbed preferences window (Grid / Behaviour / Keys / Updates). Keys tab: "Drag Trigger" section uses a click-to-record `ShortcutRecorderRow` (backed by `RecorderState: ObservableObject`); "Snap Modifiers" section retains single-modifier pickers. Recorder tracks the last state active before the first key release (snapshots only on press events) so releasing keys in any order commits the correct combination. Escape cancels recording.

### Key implementation notes
- App Sandbox is **disabled** (`ENABLE_APP_SANDBOX = NO`) — required for global event monitoring and window manipulation.
- **Trigger shortcut** (default FN/Globe) is user-configurable as a modifier-only combination or modifier+key combination (e.g. ⌃⌥F), recorded via a click-to-record UI. Persisted as JSON. **Snap modifier keys** (default Shift for windows, Control for grid) remain single-modifier pickers. All keys are read live at event time.
- **Event interception architecture**: one `CGEventTap` at `.cgSessionEventTap`/`.headInsertEventTap` handles everything. `flagsChanged` events update modifier state and are passed through. `keyDown`/`keyUp` events update key state; if they match the trigger shortcut (key code + required modifiers), they are **suppressed** (return `nil`) so no other app receives them. Mouse events are suppressed when the trigger is active.
- **Drag interaction**: trigger shortcut + left mouse starts a drag. Releasing the trigger does not end the drag — only mouse-up does. Snap mode is determined per-drag-event: snap-to-windows key → snap to other window edges (always nearest, no threshold), snap-to-grid key → snap to grid (always nearest, no threshold), neither → no snapping.
- **Window-snap move**: snaps the nearest of the moved window's four edges to the nearest candidate edge. When two edges are equidistant the left/top edge wins.
- **Move + grid snap**: snaps window to a grid position determined by cursor location. Width = one cell width. Height is cursor-position-aware: cursor in top half of its row → 1 cell height; cursor in bottom half and a row exists below → 2 cells; cursor within 25 % of a cell height from the screen bottom (3+ row grids only) → full screen height.
- **Move + no snap / window snap**: window keeps its original size. Releasing the snap modifier mid-drag restores original size automatically.
- **Resize zones**: any of the four edges when the click is within the outer 25 % of the corresponding dimension; corners activate both adjacent edges simultaneously. Centre clicks are move.
- **Own-window drag**: when the target window belongs to Gridwell's own PID (e.g. the Settings window), `WindowManipulator` uses `NSWindow.setFrame` on the main thread instead of the AX API, which would crash.
- **Raise on drag**: when enabled (default), the interacted window and its owning app are brought to the front at drag start. Configurable in Behaviour tab.
- **Opening the Settings window**: use the `SettingsButton` view (defined in `GridwellApp.swift`) which captures `@Environment(\.openSettings)` — this is the correct SwiftUI API on macOS 14+. Do **not** use `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)`: that selector is deprecated and produces the runtime warning *"Please use SettingsLink for opening the Settings scene."*
- **Bringing any window to front**: because the app normally runs as a `.accessory` (no Dock icon), windows opened from the menu bar will not receive focus unless the app is first promoted to `.regular` policy and activated. Always call `await activateAppForUI()` (defined in `GridwellApp.swift`) before showing any new window. The `AppDelegate`'s `NSWindow.willCloseNotification` observer automatically reverts the policy back to `.accessory` once all key windows are closed.
- **Sparkle gentle reminders**: background update checks show an "Update Available…" menu item rather than a hidden alert.
- `CGEvent.location`, `CGWindowListCopyWindowInfo`, and `AXUIElement` position/size all use CoreGraphics coordinates (origin top-left of primary screen, Y down) — no conversion needed between them.
- `NSScreen` identity in `ForEach` uses `displayID` (`CGDirectDisplayID` from `deviceDescription`) — stable across layout passes. Screen list is captured in `@State` on `onAppear` rather than queried directly in `body`.

## Stages
1. ✅ Create the basic skeleton framework of the application with these items:
  - An empty preference Window and a menu item for opening it (shortcut CMD ;)
  - The means to intercept modifier key changes
  - The means of determining the positions and sizes of all windows on screen.

2. ✅ Implementing the mouse interaction
  - Recognize a mouse left button down if the configured modifier keys are held down (hardcoded to FN key)
  - Recognize which window is being interacted with
  - Intercept/suppress mouse events (via CGEventTap) so underlying windows do not react
  - Track mouse dragging until mouse button is released (logs coordinates to console)

3. ✅ Implement the means to modify the position and sizes of the windows on screen. For testing, simply move the window the user is interacting with (by holding down the modifier keys and pressing the mouse button) to a hard-coded, predefined location and size. 

4. ✅ Implement the user interface in the preferences window to define the custom grid.
  - Make the preferences window a tabbed window so we can later add other preferences. 
  - Take into account that there might be more than one screen. Let the user define different grids for different screens.
  - Define a reasonable default for the grid, for example, columns of full height of a number depending on the width of the screen. For widescreens, more columns. 

5. ✅ Implement the final user interaction for dragging/resizing windows on screen while taking into account the defined grid and the other windows on screen, snapping the currently interacted with window to the grid or to the other windows, whichever is nearer.

6. ✅ Add user interface in the preferences window to define the modifier keys.

7. ✅ Integrate Sparkle auto-update framework and set up distribution pipeline.
  - Sparkle 2.x added via Swift Package Manager
  - EdDSA key pair generated; public key embedded in Info.plist
  - "Check for Updates…" menu item wired up via `SPUStandardUpdaterController`
  - Gentle background-update reminders via `SPUStandardUserDriverDelegate` — shows "Update Available…" menu item instead of a hidden alert
  - "Automatically check for updates" toggle in Updates preferences tab
  - "Check for Updates…" button in Updates preferences tab (reuses `CheckForUpdatesView`, disabled while a check is already in progress)
  - Sparkle update windows now reliably open in front: `activateAppForUI()` shared helper promotes to `.regular` policy and activates before any UI is shown; used by both the settings window path and Sparkle's `activateAndCheckForUpdates()`. AppDelegate's existing `NSWindow.willCloseNotification` observer reverts to `.accessory` when all windows close.
  - Appcast hosted at `https://raw.githubusercontent.com/jdeepwell/gridwell/main/appcast.xml`
  - DMG releases published as GitHub Release assets at `https://github.com/jdeepwell/gridwell`
  - `release.sh` automates: archive + export via `xcodebuild` (app path optional), Sparkle component re-signing, DMG creation (via `create-dmg` with background image and Applications symlink), notarization, stapling, appcast generation, GitHub Release creation (DMG + all `Gridwell${BUILD}-*.delta` files), and appcast commit/push. Supports `--clobber` flag to overwrite an existing GitHub Release (delete-then-recreate). Delta files must be uploaded alongside the DMG or Sparkle raises "improperly signed" errors on update.
  - `make_dmg.sh` creates a styled test DMG without signing/notarization/GitHub upload, and opens it automatically for inspection.
  - `dmg-background.png` provides the drag-to-install background (1152×928 px, displayed at 576×464 pt on Retina).
  - Versioning uses three-level scheme (major.minor.patch). `bump_version.sh` automates version and build number updates; called automatically by `release.sh` before archiving

8. ✅ Post-1.0 refinements (shipped in v1.0.1)
  - Resize from all four window edges (left/top edges added; corners activate both adjacent edges)
  - Smarter grid snap height: cursor position within a row determines 1-cell vs 2-cell span; bottom-edge shortcut for full screen height on 3+ row grids
  - Settings window now reliably opens in front using activation policy switching and `NSApp.sendAction` to trigger the settings window directly

11. ✅ Post-1.0.2 improvements (shipped in v1.0.3)
  - **Check for Updates button in preferences**: "Check for Updates…" button added to the Updates tab in the settings window, alongside the existing automatic-check toggle. Reuses `CheckForUpdatesView` (disabled while a check is already in progress).
  - **Fully automated release pipeline**: `release.sh` now accepts an optional app path. When omitted, it archives and exports the project automatically via `xcodebuild archive` + `xcodebuild -exportArchive`, using `ExportOptions.plist` (Developer ID, team PZ44T4KUAK). `xcodebuild` stdout is suppressed; only errors (stderr) are shown.
  - **Automated version/build number bumping**: `bump_version.sh` reads the current `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from the Xcode project, increments the patch number (or accepts an explicit version), and sets the build number to `YYYYMMDDss` (today's date + two-digit serial, incremented if already used today). `release.sh` calls it automatically before archiving and accepts a `--version X.Y.Z` flag. A safety check aborts if the requested version is ≤ the current version without `--clobber`.
  - **Settings window resize fix**: all preference tabs now use `.fixedSize(horizontal: false, vertical: true)` so the window correctly resizes to each tab's content height when switching tabs.

10. ✅ Screen edges as snap targets in window-snap mode
  - In window-snap mode (FN + Shift), all four edges of every connected screen are now treated as snap candidates alongside other window edges. Works correctly with multi-monitor setups.

9. ✅ Post-1.0.1 feature additions (shipped in v1.0.2)
  - **Four-edge window snapping**: when snap-to-windows is active during a move, all four edges of the moved window (left, right, top, bottom) now snap to other window edges — not just left/top. The nearest edge wins.
  - **Drag/resize works when Gridwell is active**: the CGEventTap now covers `flagsChanged`, `keyDown`, and `keyUp` in addition to mouse events, replacing separate NSEvent global/local monitors. This single session-level tap works regardless of which app is frontmost. Own-process windows (e.g. Settings) are moved via `NSWindow.setFrame` since the AX API cannot manipulate the calling app's own windows.
  - **Configurable trigger shortcut**: the trigger is no longer limited to a single modifier key. Users can record any combination of modifiers and optionally a regular key (e.g. ⌃⌥F) via a click-to-record UI in the Keys preferences tab. Non-modifier trigger keys are fully suppressed by the CGEventTap so they do not reach any other application. Snap modifier keys remain single-modifier pickers. Old single-modifier setting is migrated automatically.

13. ✅ First-launch onboarding (unreleased)
  - After accessibility permission is granted, the waiting window transitions in place to a "You're All Set!" screen showing `where-is-gridwell.png` (annotated screenshot pointing to the menu bar icon) with a "Got it" button. Auto-dismisses after 8 seconds. Teaches new users that the app lives in the menu bar without any extra permission prompts.

12. ✅ Post-1.0.3 refinements (unreleased)
  - **Accessibility permission flow**: on first launch without accessibility permission, the app shows a modal alert offering "Open Settings" or "Quit". If the user clicks "Open Settings", System Preferences opens to the Accessibility pane and a new waiting window appears (showing `waiting-for-permissions.png` at full @2x Retina resolution plus a Quit button). The app polls `AXIsProcessTrusted()` every 0.5 s; as soon as the user grants permission the waiting window closes and event monitoring starts — no relaunch required.
  - **Settings window fix**: replaced deprecated `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)` with a `SettingsButton` SwiftUI view that uses `@Environment(\.openSettings)`, eliminating the *"Please use SettingsLink"* runtime warning.
  - **Minimum window size filter**: accessory windows (palette views, attached panels) that are below a configurable minimum width or height are now excluded from window grabbing. Defaults to 100 × 100 pt. Configurable via two steppers in the Behaviour preferences tab. Setting either value to 0 disables filtering for that dimension. Implemented in `WindowInfoProvider.refresh()` using values from `GridConfigStore`.

## Releasing

The project is on GitHub and releases are also published on GitHub. 

Here's how to use release.sh:

  release.sh — Release Script

  Builds a signed, notarized DMG, updates the Sparkle appcast, and publishes a GitHub Release.

  Prerequisites (one-time setup)

  1. Install the GitHub CLI: brew install gh && gh auth login
  2. Store Apple notarization credentials:
  xcrun notarytool store-credentials "notarytool-profile" \
    --apple-id "your@apple-id.com" \
    --team-id "PZ44T4KUAK" \
    --password "app-specific-password"

  Usage

  ./release.sh [--clobber] [--version X.Y.Z] [<path-to-exported-Gridwell.app>]

  Examples:
  ./release.sh                          # auto-bump patch, archive, and release
  ./release.sh --version 1.1.0          # release with explicit version
  ./release.sh --clobber --version 1.0.3  # re-release same version (overwrites GitHub Release)
  ./release.sh ~/Desktop/Gridwell.app   # use pre-built .app (skips archive + version bump)

  When no .app is supplied, the script bumps the version/build number automatically
  (via bump_version.sh) and archives the project. Requesting a version ≤ the current
  version without --clobber aborts with an error.

  What it does

  ┌──────┬────────────────────────────────────────────────────────────────────┐
  │ Step │                               Action                               │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 1    │ Re-signs Sparkle's XPC services and helpers with your Developer ID │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 2    │ Creates a compressed DMG in releases/                              │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 3    │ Code-signs the DMG                                                 │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 4    │ Submits the DMG to Apple for notarization (takes a few minutes)    │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 5    │ Staples the notarization ticket to the DMG                         │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 6    │ Runs generate_appcast to produce appcast.xml                       │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 7    │ Commits appcast.xml to the repo                                    │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 8    │ Creates a GitHub Release tagged vX.Y and uploads the DMG           │
  ├──────┼────────────────────────────────────────────────────────────────────┤
  │ 9    │ Pushes the appcast.xml commit so the live Sparkle feed updates     │
  └──────┴────────────────────────────────────────────────────────────────────┘

  Output

  - releases/Gridwell-X.Y.dmg — the distributable installer
  - appcast.xml — updated Sparkle feed at raw.githubusercontent.com/.../main/appcast.xml
  