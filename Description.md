We are building a macOS utility application.

The purpose of this application is window management.

The user should be able to grab windows, not only in the title bar, but anywhere in the window, while holding configurable modifier keys.

When dragging near a border, the window should be resized. When dragging near the middle, the window should be moved.

The user should be able to define a personalized grid.

When the windows are resized or moved, they should snap to this grid, or to the edges of other windows - whichever is nearer.

You are provided with the basic application template from Xcode. 

## Current Status

**Completed: Stages 1, 2, 3, 4, and 5**

### Architecture
- `GridwellApp.swift` — SwiftUI `Settings` scene, no main window on launch. CMD+; opens preferences via `SettingsLink`. Injects `GridConfigStore.shared` as an `environmentObject`.
- `AppDelegate.swift` — Requests Accessibility permission on launch (shows alert + opens System Settings if not granted). Starts monitors once trusted.
- `ModifierKeyMonitor.swift` — Global `flagsChanged` event monitor tracking FN/Globe key state (keyCode 63).
- `MouseInteractionHandler.swift` — `CGEventTap` at `.cgSessionEventTap` / `.headInsertEventTap`. Intercepts and **suppresses** left mouse down/dragged/up events when FN is held. Identifies the target window via `WindowInfoProvider`. Computes candidate frames via `GridSnapper` and forwards them to `WindowManipulator`.
- `WindowInfoProvider.swift` — Uses `CGWindowListCopyWindowInfo` to enumerate on-screen windows. Exposes `window(at: CGPoint)` for hit-testing in CoreGraphics coordinates. `WindowInfo` includes `pid` for use by the Accessibility API. When multiple windows overlap the click point, `window(at:)` re-queries the window server for a fresh front-to-back ordering (since `CGWindowListCopyWindowInfo` does not guarantee order within the same layer) and returns the genuinely topmost candidate.
- `WindowManipulator.swift` — Uses `AXUIElementCreateApplication(pid)` + `kAXPositionAttribute`/`kAXSizeAttribute` to move and resize windows via the Accessibility API. A `DispatchSourceTimer` (10 Hz) on a background serial queue applies the latest pending frame, splitting position and size changes across two ticks to avoid AX API interference.
- `GridConfigStore.swift` — `ObservableObject` singleton. Stores a `[String: ScreenGridConfig]` (columns + rows per screen) in `UserDefaults`. Screen keys use point-space dimensions only (e.g. `"2560x1440"`), falling back to appending origin when two screens share the same size. Default column count scales with screen width; default row count is 1.
- `GridSnapper.swift` — Stateless helpers for drag-zone detection, candidate frame computation, and snapping. Contains `SnapMode` enum (`.none`, `.windows`, `.grid`).
- `PreferencesView.swift` — Tabbed preferences window (Grid / Keys). Grid tab shows one `GroupBox` per connected screen with the display name, native resolution, a live grid preview (`Canvas`), and custom column/row steppers.

### Key implementation notes
- App Sandbox is **disabled** (`ENABLE_APP_SANDBOX = NO`) — required for global event monitoring and window manipulation.
- Modifier key trigger is hardcoded to the **FN/Globe key**. Secondary snap modifiers are read live from each drag event (not stored at drag start), so they can be changed mid-drag.
- Drag interaction: FN + left mouse starts a drag. Releasing FN does not end the drag — only mouse-up does. Snap mode is determined per-drag-event: Shift → snap to other window edges (always nearest, no threshold), Control → snap to grid (always nearest, no threshold), neither → no snapping.
- **Move + grid snap**: snaps window to the nearest full grid cell (position and size). Position is applied on tick 1, size on tick 2 (once the frame stabilises) to avoid the AX API resetting size when position is set in the same call. Width is always snapped to the cell width. Height is snapped to the full screen height when the window lands in the uppermost grid row, and to the cell height in all other rows.
- **Move + no snap / window snap**: window keeps its original size. Releasing the snap modifier mid-drag restores original size automatically (candidate frame always starts from `dragStartWindowFrame`).
- **Resize zones**: right edge (outer 25 % of width), bottom edge (outer 25 % of height), or bottom-right corner (both). Left/top edges are treated as move.
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

6. Add user interface in the preferences window to define the modifier keys.


