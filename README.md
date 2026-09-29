# Gridwell

A macOS utility for moving and resizing windows by dragging anywhere in them — not just the title bar — with optional snapping to a custom grid or to the edges of other windows.

---
![Gridwell Illustration](<Assets/hero image.png>)

---

## Features

- **Drag/Resize from ANYWHERE** — hold the trigger modifier key (default: FN / Globe) and left-click anywhere inside a window to move or anywhere near an edge to resize it – you can release the trigger modifier key during interaction. Alternatively, use a configurable extra mouse button (middle, back, forward, etc.) with no modifier key required.
- **No title bar gap or edge sniping** — you do not need to aim for that one free gap in a window's title bar or its edge to move or resize it. The trigger key and extra mouse button work anywhere in the window.
- **Snap to grid** — hold the grid snap combination (default: Control) while dragging to snap the window to the nearest cell of your custom grid.
- **Snap to windows** — hold the window snap combination (default: Shift) while dragging to align the window's edges with the edges of other on-screen windows.
- **Exact modifier combinations** — every feature is activated by its own modifier combination (e.g. ⌃⌥), and only when exactly that combination is held. Combinations can be pressed, changed, or released at any point during a drag and the window responds immediately.
- **Edge shrink** — hold the edge shrink combination while dragging a window towards the left or right screen edge, and it shrinks the deeper it goes into the edge zone. Its original size is remembered for the next time you pick it up. Inspired by [Scott Jenson](https://jenson.org/) - see his talk at https://youtu.be/V7AfAcQwLW0?t=1819
- **Bottom minimize** — with the same combination held, release a window in the bottom zone of the screen to minimize it.
- **Per-screen grids** — configure a different column and row count for each connected display.
- **Fully configurable keys** — the drag trigger (modifier key combination, modifier+key shortcut, or mouse button) and the modifier combinations for snap-to-windows, snap-to-same-app-windows, snap-to-grid, and edge shrink are all set in preferences and persist across launches.
- **No title bar required** — works on windows that have non-standard or hidden title bars.
- **Per-app window snapping** — hold a dedicated combination (default: Option) to snap only to windows belonging to the same application.
- **Mouse button app exceptions** — exclude specific apps from the mouse button trigger so native behaviour (e.g. middle-click auto-scroll in browsers) is preserved.
- **Minimum window size filter** — small accessory windows below a configurable threshold are excluded from drag and resize interactions.
- **Configurable resize border** — adjust how wide the edge zone is that triggers a resize rather than a move, using a percentage of the window dimension (default 25 %) and a minimum pixel floor (default 40 pt).
- **Raise on drag** — optionally bring the target window and its app to the front when you start dragging (enabled by default).

## How it works

### Moving a window

Hold the **trigger key** (default: FN / Globe) and left-click in the middle of any window. Drag to move it. Release the mouse button to finish. Alternatively, press the configured **mouse button** (middle, back, forward, etc.) without any modifier key.

### Resizing a window

Hold the **trigger key** and left-click within the **outer 25 %** of any edge (left, right, top, or bottom). Drag to resize. Corners activate both adjacent edges simultaneously.

### Snapping

While dragging, hold a modifier combination:

| Combination (default) | Effect |
|--------------------|--------|
| **Control** | Snap to grid — window jumps to a grid cell (see below) |
| **Shift** | Snap to windows — window edges align with edges of all on-screen windows |
| **Option** | Snap to same-app windows — like Shift, but limited to the same application |
| *(none)* | Free movement, no snapping |

A feature is active only while **exactly** its combination is held — with grid snap on Control, holding Control + Option does not snap to the grid. The drag trigger's modifier counts as a held key too: think of the trigger as a key that only starts the drag. With the default FN trigger, start the drag, **release FN**, then hold the snap combination. Keeping just the trigger held gives a plain drag.

Combinations can be pressed, changed, or released at any point during a drag, and the window responds immediately.

#### Grid snap — height behaviour

When snapping to the grid, the window height is determined by where the cursor sits within the row:

- **Top half of a row** — window height = one cell.
- **Bottom half of a row** — window height = two cells (current row + the one below), provided a row below exists.
- **Very near the bottom edge of the screen** (grids with more than 2 rows only) — window height = full screen height, anchored to the top of the screen.

### Edge shrink and bottom minimize

Assign a combination to **Edge shrink** in the Keys tab (disabled by default). While moving a window, hold that combination:

- **Side zones** — move towards the left or right screen edge. Inside the side zone the window shrinks the deeper you go, down to the minimum shrink width. The spot you grabbed stays under the cursor, and the window never leaves the screen sideways. Release the mouse to leave the window shrunk; its original size is remembered and restored the next time you pick it up with the combination held.
- **Bottom zone** — move into the bottom zone between the side zones. A highlighted strip appears; release the mouse to minimize the window. It is moved back to where the drag started first, so it reappears there when restored from the Dock. Release the combination before the mouse to cancel.
- **Screen lock** — while the combination is held, the window stays on its current screen, and edges shared with another monitor behave like outer screen edges. Release the combination to return the window to its original size and move it freely to another screen; press it again to shrink there.


## Preferences

Open preferences with **⌘ ;** or via the menu bar.

### Grid tab

Configure the number of columns and rows for each connected screen. A live preview shows the current grid layout scaled to the screen's aspect ratio.

### Behaviour tab

Configure raise-on-drag, minimum window size (width and height below which windows are excluded from interactions), and the resize border (a percentage of the window dimension plus a minimum pixel floor that together determine how deep the edge zone is that triggers a resize rather than a move).

The **Screen Edges** card sets the edge shrink zones: the side zone width (a percentage of each screen's width, default 5 %), the bottom zone height (default 40 pt), and the minimum shrink width (default 400 pt). While you drag one of the zone sliders, the zones are shown on all screens. A window is never shrunk below the minimum window size, so it can always be picked up again.

### Keys tab

Set the drag trigger (modifier key combination, modifier+key shortcut, or mouse button) and, in the **Modifier Combinations** card, the combinations for snap-to-all-windows, snap-to-same-app-windows, snap-to-grid, and edge shrink. Click a badge, hold the modifier keys, then release them; **Disable** turns a feature off. A combination can only be used by one feature. A separate card lets you define mouse button app exceptions — apps where the mouse button trigger is disabled so native behaviour is preserved.

### Updates tab

Toggle automatic update checks. This reflects the choice made at first launch and can be changed at any time.

---

## Requirements

- macOS 15.7 Sequoia or later
- **Accessibility permission** — Gridwell uses the Accessibility API to move and resize windows. On first launch it shows a prompt to open System Settings → Privacy & Security → Accessibility. The app must be trusted before monitoring starts.


## Building

Gridwell has no external dependencies. Clone the repo and open the Xcode project:

```sh
git clone https://github.com/yourname/Gridwell.git
cd Gridwell
open Gridwell.xcodeproj
```

Select the **Gridwell** scheme, choose your Mac as the run destination, and press **⌘ R**. App Sandbox is disabled in the project (required for global event monitoring and window manipulation via the Accessibility API).

