We are building a macOS utility application.

The purpose of this application is window management.

The user should be able to grab windows, not only in the title bar, but anywhere in the window, while holding configurable modifier keys.

When dragging near a border, the window should be resized. When dragging near the middle, the window should be moved.

The user should be able to define a personalized grid.

When the windows are resized or moved, they should snap to this grid, or to the edges of other windows - whichever is nearer.

You are provided with the basic application template from Xcode. 

## Current Status

**Completed: Stages 1, 2 and 3**

### Architecture
- `GridwellApp.swift` — SwiftUI `Settings` scene, no main window on launch. CMD+; opens preferences via `SettingsLink`.
- `AppDelegate.swift` — Requests Accessibility permission on launch (shows alert + opens System Settings if not granted). Starts monitors once trusted.
- `ModifierKeyMonitor.swift` — Global `flagsChanged` event monitor tracking FN/Globe key state (keyCode 63).
- `MouseInteractionHandler.swift` — `CGEventTap` at `.cgSessionEventTap` / `.headInsertEventTap`. Intercepts and **suppresses** left mouse down/dragged/up events when FN is held. Identifies the target window via `WindowInfoProvider`. On mouse-up, calls `WindowManipulator` to move the window to a hard-coded test frame.
- `WindowInfoProvider.swift` — Uses `CGWindowListCopyWindowInfo` to enumerate on-screen windows. Exposes `window(at: CGPoint)` for hit-testing in CoreGraphics coordinates. `WindowInfo` includes `pid` for use by the Accessibility API.
- `WindowManipulator.swift` — Uses `AXUIElementCreateApplication(pid)` + `kAXPositionAttribute`/`kAXSizeAttribute` to move and resize windows via the Accessibility API.
- `PreferencesView.swift` — Placeholder SwiftUI view.

### Key implementation notes
- App Sandbox is **disabled** (`ENABLE_APP_SANDBOX = NO`) — required for global event monitoring and window manipulation.
- Modifier key trigger is hardcoded to the **FN/Globe key**. Device-specific left/right modifier bits are not used (they are unreliable in mouse events; tracked via `flagsChanged` in `ModifierKeyMonitor` instead).
- `CGEvent.location`, `CGWindowListCopyWindowInfo`, and `AXUIElement` position/size all use CoreGraphics coordinates (origin top-left of primary screen, Y down) — no conversion needed between them.
- Stage 3 uses a hard-coded test frame `(x: 100, y: 100, width: 800, height: 600)` in `MouseInteractionHandler.testFrame`; this will be replaced with real drag logic in Stage 5.

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

4. Implement the user interface in the preferences window to define the custom grid.
  - Make the preferences window a tabbed window so we can later add other preferences. 
  - Take into account that there might be more than one screen. Let the user define different grids for different screens.
  - Define a reasonable default for the grid, for example, columns of full height of a number depending on the width of the screen. For widescreens, more columns. 

5. Implement the final user interaction for dragging/resizing windows on screen while taking into account the defined grid and the other windows on screen, snapping the currently interacted with window to the grid or to the other windows, whichever is nearer.

6. Add user interface in the preferences window to define the modifier keys.


