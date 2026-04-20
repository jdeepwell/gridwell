We are building a macOS utility application.

The purpose of this application is window management.

The user should be able to grab windows, not only in the title bar, but anywhere in the window, while holding configurable modifier keys.

When dragging near a border, the window should be resized. When dragging near the middle, the window should be moved.

The user should be able to define a personalized grid.

When the windows are resized or moved, they should snap to this grid, or to the edges of other windows - whichever is nearer.

You are provided with the basic application template from Xcode. 

## Current Status

**Completed: Stages 1, 2, 3, 4, 5, 6, menu bar conversion, deployment/distribution, post-1.0 refinements, and post-1.0.1 feature additions. Current release: v1.0.2.**

### Architecture
- `GridwellApp.swift` — SwiftUI `Window` (hidden, 1×1) + `MenuBarExtra` + `Settings` scenes. App runs as a menu bar agent (`LSUIElement = YES`): no Dock icon, no App Switcher entry. Menu bar icon uses SF Symbol `rectangle.3.group`. Menu contains: Settings… (⌘,), Update Available… (conditional), Check for Updates…, About Gridwell, Quit Gridwell (⌘Q). The hidden `Window` scene must be declared before `Settings` so that `@Environment(\.openSettings)` resolves correctly. `HiddenWindowView` receives an `openSettingsRequest` notification, temporarily promotes the app to `.regular` activation policy, activates, calls `openSettings()`, then forces the window to front — the only reliable way to raise a settings window for an `.accessory`-policy app on macOS 15. `SparkleManager` owns the `SPUStandardUpdaterController` and implements `SPUStandardUserDriverDelegate` for gentle background-update reminders. Settings scene injects `GridConfigStore.shared` and `SparkleManager` as environment objects.
- `AppDelegate.swift` — Requests Accessibility permission on launch (shows alert + opens System Settings if not granted). Starts monitors once trusted. Observes `NSWindow.willCloseNotification` to revert the app to `.accessory` activation policy when the last key window closes.
- `ModifierKeyMonitor.swift` — Pure state store for trigger detection. Tracks current modifier flags and non-modifier key state. Exposes `handleFlagsChanged(_:CGEvent)`, `handleKeyDown(keyCode:)`, `handleKeyUp(keyCode:)` — called directly by the CGEventTap in `MouseInteractionHandler`. Computes `isTriggerActive` from both modifier and key state against the configured `TriggerShortcut`.
- `MouseInteractionHandler.swift` — Single `CGEventTap` at `.cgSessionEventTap` / `.headInsertEventTap` covering **all** intercepted event types: `leftMouseDown/Dragged/Up` (drag/resize), `flagsChanged` (modifier tracking, always passed through), `keyDown/keyUp` (key tracking; suppressed if they match the trigger shortcut). This single session-level tap covers both app-active and app-inactive cases. Identifies the target window via `WindowInfoProvider`. Computes candidate frames via `GridSnapper` and forwards them to `WindowManipulator`.
- `WindowInfoProvider.swift` — Uses `CGWindowListCopyWindowInfo` to enumerate on-screen windows. Exposes `window(at: CGPoint)` for hit-testing in CoreGraphics coordinates. `WindowInfo` includes `pid` for use by the Accessibility API. When multiple windows overlap the click point, `window(at:)` re-queries the window server for a fresh front-to-back ordering (since `CGWindowListCopyWindowInfo` does not guarantee order within the same layer) and returns the genuinely topmost candidate. Phantom/ghost windows are excluded via four combined guards: `layer == 0` (drops menu bar items and system overlays), `alpha > 0` (drops transparent utility surfaces), a system-owner blocklist (`Window Server`, `Dock`, `SystemUIServer`, `Control Center`, etc.), and non-zero frame size.
- `WindowManipulator.swift` — Uses `AXUIElementCreateApplication(pid)` + `kAXPositionAttribute`/`kAXSizeAttribute` to move and resize windows via the Accessibility API. When the target window belongs to Gridwell's own process, uses `NSWindow.setFrame` (AppKit) instead — the AX API cannot manipulate the calling app's own windows. A `DispatchSourceTimer` (10 Hz) on a background serial queue applies the latest pending frame. Each frame is applied via a `setFrame` helper that sets **size before position** (to prevent the system from repositioning the window after a size change) and uses a **read-back retry loop** (up to 5 attempts) that verifies **both position and size** before declaring success. `AXEnhancedUserInterface` is intentionally never touched, as disabling it causes VoiceOver regressions and Chromium UI freezes. `raiseWindow(pid:)` brings the target window and its app to the front at drag start.
- `GridConfigStore.swift` — `ObservableObject` singleton. Stores a `[String: ScreenGridConfig]` (columns + rows per screen), `raiseWindowOnDrag: Bool`, a `TriggerShortcut` (JSON-encoded), and two `ModifierKey` snap keys in `UserDefaults`. Screen keys use point-space dimensions only (e.g. `"2560x1440"`), falling back to appending origin when two screens share the same size. Includes one-time migration from the legacy single-`ModifierKey` trigger format.
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
- **Settings window activation**: opening settings temporarily promotes the app to `.regular` policy, activates it, calls `openSettings()` via a hidden SwiftUI window, then reverts to `.accessory` when the window closes.
- **Sparkle gentle reminders**: background update checks show an "Update Available…" menu item rather than a hidden alert.
- `CGEvent.location`, `CGWindowListCopyWindowInfo`, and `AXUIElement` position/size all use CoreGraphics coordinates (origin top-left of primary screen, Y down) — no conversion needed between them.
- `NSScreen` objects are stable singletons per display — `ForEach(id: \.self)` is safe.

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
  - Appcast hosted at `https://raw.githubusercontent.com/jdeepwell/gridwell/main/appcast.xml`
  - DMG releases published as GitHub Release assets at `https://github.com/jdeepwell/gridwell`
  - `release.sh` automates: Sparkle component re-signing, DMG creation, notarization, stapling, appcast generation, GitHub Release creation, and appcast commit/push
  - Versioning uses three-level scheme (major.minor.patch); only `MARKETING_VERSION` in Xcode needs updating between releases

8. ✅ Post-1.0 refinements (shipped in v1.0.1)
  - Resize from all four window edges (left/top edges added; corners activate both adjacent edges)
  - Smarter grid snap height: cursor position within a row determines 1-cell vs 2-cell span; bottom-edge shortcut for full screen height on 3+ row grids
  - Settings window now reliably opens in front using activation policy switching and a hidden SwiftUI window for the `openSettings()` environment context

9. ✅ Post-1.0.1 feature additions (shipped in v1.0.2)
  - **Four-edge window snapping**: when snap-to-windows is active during a move, all four edges of the moved window (left, right, top, bottom) now snap to other window edges — not just left/top. The nearest edge wins.
  - **Drag/resize works when Gridwell is active**: the CGEventTap now covers `flagsChanged`, `keyDown`, and `keyUp` in addition to mouse events, replacing separate NSEvent global/local monitors. This single session-level tap works regardless of which app is frontmost. Own-process windows (e.g. Settings) are moved via `NSWindow.setFrame` since the AX API cannot manipulate the calling app's own windows.
  - **Configurable trigger shortcut**: the trigger is no longer limited to a single modifier key. Users can record any combination of modifiers and optionally a regular key (e.g. ⌃⌥F) via a click-to-record UI in the Keys preferences tab. Non-modifier trigger keys are fully suppressed by the CGEventTap so they do not reach any other application. Snap modifier keys remain single-modifier pickers. Old single-modifier setting is migrated automatically.

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

  ./release.sh <path-to-exported-Gridwell.app>

  Example:
  ./release.sh ~/Desktop/Gridwell.app

  The .app must be an exported archive from Xcode (not the build product). The script reads the version number directly from the app's Info.plist.

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
  