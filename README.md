# Gridwell

A macOS utility for moving and resizing windows by dragging anywhere in them — not just the title bar — with optional snapping to a custom grid or to the edges of other windows.

---

<!-- SCREENSHOT: Animated GIF or screen recording showing a window being dragged from its body (not title bar), with the snap-to-grid modifier held, snapping into a grid cell. Ideally shows two or three different apps side by side to illustrate the grid layout. -->
> **[Screenshot — window drag + grid snap in action]**

---

## Features

- **Drag from anywhere** — hold the trigger modifier key (default: FN / Globe) and left-click anywhere inside a window to move or resize it, no matter where your cursor is – you can release the trigger modifier key during interaction.
- **Move or resize in one gesture** — the drag zone is determined by cursor position: clicking near the right or bottom edge resizes, clicking anywhere else moves.
- **Snap to grid** — hold the grid snap modifier (default: Control) while dragging to snap the window to the nearest cell of your custom grid.
- **Snap to windows** — hold the window snap modifier (default: Shift) while dragging to align the window's edges with the edges of other on-screen windows.
- **Snap modifiers work mid-drag** — you can change or release a snap modifier at any point during a drag and the window responds immediately.
- **Per-screen grids** — configure a different column and row count for each connected display.
- **Fully configurable modifier keys** — all three modifier keys (trigger, snap-to-windows, snap-to-grid) are set in preferences and persist across launches.
- **No title bar required** — works on windows that have non-standard or hidden title bars.
- **Raise on drag** — optionally bring the target window and its app to the front when you start dragging (enabled by default).

## How it works

### Moving a window

Hold the **trigger key** (default: FN / Globe) and left-click in the middle of any window. Drag to move it. Release the mouse button to finish.

### Resizing a window

Hold the **trigger key** and left-click within the **outer 25 %** of any edge (left, right, top, or bottom). Drag to resize. Corners activate both adjacent edges simultaneously.

### Snapping

While dragging, hold an additional modifier:

| Modifier (default) | Effect |
|--------------------|--------|
| **Control** | Snap to grid — window jumps to a grid cell (see below) |
| **Shift** | Snap to windows — window edges align with edges of other on-screen windows |
| *(neither)* | Free movement, no snapping |

Snap modifiers can be held or released at any point during a drag.

#### Grid snap — height behaviour

When snapping to the grid, the window height is determined by where the cursor sits within the row:

- **Top half of a row** — window height = one cell.
- **Bottom half of a row** — window height = two cells (current row + the one below), provided a row below exists.
- **Very near the bottom edge of the screen** (grids with more than 2 rows only) — window height = full screen height, anchored to the top of the screen.

---

<!-- SCREENSHOT: Side-by-side of the same desktop with snapping off (window mid-drag, free position) and snapping on (window locked to a grid cell). Shows the visual effect of grid snapping. -->
> **[Screenshot — free drag vs. grid-snapped drag comparison]**

---

## Preferences

Open preferences with **⌘ ;** or via the menu bar.

### Grid tab

Configure the number of columns and rows for each connected screen. A live preview shows the current grid layout scaled to the screen's aspect ratio.

<!-- SCREENSHOT: Preferences window open on the Grid tab, showing one or two GroupBox sections (one per screen) with the grid preview canvas, column stepper, and row stepper visible. -->
> **[Screenshot — Preferences → Grid tab]**

### Behaviour tab

Toggle whether the target window is raised to the front when you start dragging it.

### Keys tab

Set the three modifier keys independently using dropdown menus. Available choices for each: FN / Globe (fn), Shift (⇧), Control (⌃), Option (⌥), Command (⌘).

<!-- SCREENSHOT: Preferences window open on the Keys tab, showing the "Drag Trigger" GroupBox with a key picker and the "Snap Modifiers" GroupBox with two key pickers. -->
> **[Screenshot — Preferences → Keys tab]**

---

## Requirements

- macOS 13 Ventura or later
- **Accessibility permission** — Gridwell uses the Accessibility API to move and resize windows. On first launch it shows a prompt to open System Settings → Privacy & Security → Accessibility. The app must be trusted before monitoring starts.

<!-- SCREENSHOT: The accessibility permission alert dialog shown on first launch, with the "Open Settings" button visible. -->
> **[Screenshot — Accessibility permission prompt on first launch]**

## Building

Gridwell has no external dependencies. Clone the repo and open the Xcode project:

```sh
git clone https://github.com/yourname/Gridwell.git
cd Gridwell
open Gridwell.xcodeproj
```

Select the **Gridwell** scheme, choose your Mac as the run destination, and press **⌘ R**. App Sandbox is disabled in the project (required for global event monitoring and window manipulation via the Accessibility API).

