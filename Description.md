We are building a macOS utility application.

The purpose of this application is window management.

The user should be able to grab windows, not only in the title bar, but anywhere in the window, while holding configurable modifier keys.

When dragging near a border, the window should be resized. When dragging near the middle, the window should be moved.

The user should be able to define a personalized grid.

When the windows are resized or moved, they should snap to this grid, or to the edges of other windows - whichever is nearer.

You are provided with the basic application template from Xcode. 

## Current Status

**Completed: Stages 1, 2, 3, 4, 5, 6, menu bar conversion, deployment/distribution, and post-1.0 refinements. Current release: v1.0.1.**

### Architecture
- `GridwellApp.swift` — SwiftUI `Window` (hidden, 1×1) + `MenuBarExtra` + `Settings` scenes. App runs as a menu bar agent (`LSUIElement = YES`): no Dock icon, no App Switcher entry. Menu bar icon uses SF Symbol `rectangle.3.group`. Menu contains: Settings… (⌘,), Update Available… (conditional), Check for Updates…, About Gridwell, Quit Gridwell (⌘Q). The hidden `Window` scene must be declared before `Settings` so that `@Environment(\.openSettings)` resolves correctly. `HiddenWindowView` receives an `openSettingsRequest` notification, temporarily promotes the app to `.regular` activation policy, activates, calls `openSettings()`, then forces the window to front — the only reliable way to raise a settings window for an `.accessory`-policy app on macOS 15. `SparkleManager` owns the `SPUStandardUpdaterController` and implements `SPUStandardUserDriverDelegate` for gentle background-update reminders. Settings scene injects `GridConfigStore.shared` and `SparkleManager` as environment objects.
- `AppDelegate.swift` — Requests Accessibility permission on launch (shows alert + opens System Settings if not granted). Starts monitors once trusted. Observes `NSWindow.willCloseNotification` to revert the app to `.accessory` activation policy when the last key window closes.
- `ModifierKeyMonitor.swift` — Global `flagsChanged` event monitor tracking FN/Globe key state (keyCode 63).
- `MouseInteractionHandler.swift` — `CGEventTap` at `.cgSessionEventTap` / `.headInsertEventTap`. Intercepts and **suppresses** left mouse down/dragged/up events when FN is held. Identifies the target window via `WindowInfoProvider`. Computes candidate frames via `GridSnapper` and forwards them to `WindowManipulator`.
- `WindowInfoProvider.swift` — Uses `CGWindowListCopyWindowInfo` to enumerate on-screen windows. Exposes `window(at: CGPoint)` for hit-testing in CoreGraphics coordinates. `WindowInfo` includes `pid` for use by the Accessibility API. When multiple windows overlap the click point, `window(at:)` re-queries the window server for a fresh front-to-back ordering (since `CGWindowListCopyWindowInfo` does not guarantee order within the same layer) and returns the genuinely topmost candidate. Phantom/ghost windows are excluded via four combined guards: `layer == 0` (drops menu bar items and system overlays), `alpha > 0` (drops transparent utility surfaces), a system-owner blocklist (`Window Server`, `Dock`, `SystemUIServer`, `Control Center`, etc.), and non-zero frame size.
- `WindowManipulator.swift` — Uses `AXUIElementCreateApplication(pid)` + `kAXPositionAttribute`/`kAXSizeAttribute` to move and resize windows via the Accessibility API. A `DispatchSourceTimer` (10 Hz) on a background serial queue applies the latest pending frame. Each frame is applied via a `setFrame` helper that sets **size before position** (to prevent the system from repositioning the window after a size change) and uses a **read-back retry loop** (up to 5 attempts) that verifies **both position and size** before declaring success — verifying only position would miss cases where size lags (e.g. when crossing between screens with very different cell dimensions). `AXEnhancedUserInterface` is intentionally never touched, as disabling it causes VoiceOver regressions and Chromium UI freezes. `raiseWindow(pid:)` brings the target window and its app to the front at drag start by combining `kAXMainAttribute` (raises window within app), `kAXFrontmostAttribute` (activates the app via AX layer), and `NSRunningApplication.activate()`.
- `GridConfigStore.swift` — `ObservableObject` singleton. Stores a `[String: ScreenGridConfig]` (columns + rows per screen) and a `raiseWindowOnDrag: Bool` flag in `UserDefaults`. Screen keys use point-space dimensions only (e.g. `"2560x1440"`), falling back to appending origin when two screens share the same size. Default column count scales with screen width; default row count is 1. `raiseWindowOnDrag` defaults to `true`.
- `GridSnapper.swift` — Stateless helpers for drag-zone detection, candidate frame computation, and snapping. Contains `SnapMode` enum (`.none`, `.windows`, `.grid`). Screen detection for snapping uses the **cursor position** (not the candidate window frame) via `containingScreen(for: CGPoint)`, which avoids false screen switches when a tall window extends past a screen edge. The `cgFrame` helper converts NSScreen → CG coordinates using `NSScreen.screens.first` (the stable primary display) for the Y-flip height — `NSScreen.main` must not be used as it tracks the key-window screen and changes during drags. Grid cell selection uses `floor` of the cursor offset within the screen so the window only advances to the next cell when the cursor physically enters it.
- `ModifierKey.swift` — `ModifierKey` enum with cases `.fn`, `.shift`, `.control`, `.option`, `.command`. Each carries a display name, symbol (fn ⇧ ⌃ ⌥ ⌘), `NSEvent.ModifierFlags` flag (for trigger detection), and `CGEventFlags` flag (for snap detection during drags).
- `PreferencesView.swift` — Tabbed preferences window (Grid / Behaviour / Keys / Updates). Grid tab shows one `GroupBox` per connected screen with the display name, native resolution, a live grid preview (`Canvas`), and custom column/row steppers. Behaviour tab has a toggle for "Raise window to front when dragging". Keys tab has two `GroupBox` sections — "Drag Trigger" (picker for the trigger key) and "Snap Modifiers" (pickers for snap-to-windows and snap-to-grid keys). Updates tab has a toggle for "Automatically check for updates", backed by `SparkleManager.automaticallyChecksForUpdates` with manual `objectWillChange.send()` so the toggle reflects changes correctly in SwiftUI.

### Key implementation notes
- App Sandbox is **disabled** (`ENABLE_APP_SANDBOX = NO`) — required for global event monitoring and window manipulation.
- All three modifier keys are user-configurable and persisted in `UserDefaults`: **trigger key** (default FN/Globe), **snap-to-windows key** (default Shift), **snap-to-grid key** (default Control). All three are read live at event time, so changes in preferences take effect immediately without restarting.
- Drag interaction: trigger key + left mouse starts a drag. Releasing the trigger does not end the drag — only mouse-up does. Snap mode is determined per-drag-event: snap-to-windows key → snap to other window edges (always nearest, no threshold), snap-to-grid key → snap to grid (always nearest, no threshold), neither → no snapping.
- **Move + grid snap**: snaps window to a grid position determined by cursor location. Width = one cell width. Height is cursor-position-aware: cursor in top half of its row → 1 cell height; cursor in bottom half and a row exists below → 2 cells; cursor within 25 % of a cell height from the screen bottom (3+ row grids only) → full screen height. Size is always set before position to prevent the system from overwriting the target position after a size change. A read-back retry loop (up to 5 attempts) verifies both position and size.
- **Move + no snap / window snap**: window keeps its original size. Releasing the snap modifier mid-drag restores original size automatically (candidate frame always starts from `dragStartWindowFrame`).
- **Resize zones**: any of the four edges when the click is within the outer 25 % of the corresponding dimension; corners activate both adjacent edges simultaneously. Centre clicks (no edge within threshold) are move.
- **Raise on drag**: when enabled (default), the interacted window and its owning app are brought to the front at drag start. Configurable in the Behaviour preferences tab.
- **Settings window activation**: because `LSUIElement` apps have `.accessory` policy, macOS refuses to raise their windows above other apps. Opening settings temporarily promotes the app to `.regular` policy (Dock icon briefly appears), activates it, calls `openSettings()` via a hidden SwiftUI window that holds the `@Environment(\.openSettings)` context, then reverts to `.accessory` when the window closes.
- **Sparkle gentle reminders**: background update checks show an "Update Available…" menu item rather than a hidden alert. `supportsGentleScheduledUpdateReminders` returns `true` to suppress the Sparkle console warning.
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

