# Feature: Modifier Combinations, Edge Shrink & Bottom Minimize

Status: **in progress** — Step 1 done and verified. Step 2 implemented, awaiting manual testing.

## Overview

Two new behaviours for Gridwell move drags, near the screen edges:

- **Edge shrink** — dragging a window into a left or right edge zone shrinks it progressively; the deeper into the zone, the smaller.
- **Bottom minimize** — releasing a window inside a bottom edge zone minimizes it.

Both are activated by a dedicated modifier combination. Because this adds yet another modifier-driven feature, all feature modifiers are first upgraded from single keys to **exact modifier combinations** (Step 1).

Scope: only drags performed by Gridwell (trigger shortcut or mouse-button trigger). Native title-bar drags are not affected.

---

## Step 1 — Exact modifier combinations

### Model
- New `ModifierCombination` type: a set of modifiers (fn ⌃ ⌥ ⇧ ⌘). Empty = feature disabled.
- Replaces the single `ModifierKey` for these features:

| Feature | Default |
|---|---|
| Snap to all windows | ⇧ |
| Snap to same-app windows | ⌥ |
| Snap to grid | ⌃ |
| Edge shrink / bottom minimize | disabled |

### Matching
- A feature is active when the currently held modifiers **equal** its combination exactly (e.g. with grid snap = ⌃, holding ⌃⌥ does *not* activate grid snap).
- The drag trigger's modifiers receive no special treatment. The trigger is thought of as a temporary key that only initiates the drag; the user normally releases it during the drag and then presses a feature combination. Keeping the trigger held just means "plain drag" — unless a feature's combination equals the held keys (e.g. trigger fn and a feature also on fn), in which case that feature activates immediately, which is acceptable.
- Two features may not share the same combination (rejected in the UI). Overlap with the trigger's modifiers is allowed.

### Migration (settings version 3 → 4)
- Each stored single snap key becomes a one-key combination (⇧ → "⇧"). The trigger modifier is **not** added.
- Edge shrink combination starts empty (disabled).

### UI — Keys tab
- The "Snap Modifiers" card becomes "Modifier Combinations" with one click-to-record row per feature (same interaction as the drag trigger recorder, modifier-only mode: non-modifier keys ignored, Escape cancels, commit on release of all keys).
- Each row has a "Disable" button that clears the combination.
- A conflicting combination is rejected with an inline message.

### Behaviour change for existing users
Today, holding fn+⇧ snaps. After the update, snapping only activates once fn is released (held keys must equal "⇧" exactly). Must be noted in CHANGELOG and README.

---

## Step 2 — Edge shrink & bottom minimize

### Activation
- Only during **move** drags (not resize drags), from either trigger, while the shrink combination is held exactly.
- Pressing the combination mid-drag activates it immediately. Releasing it mid-drag returns the window to its original size at the real cursor position (consistent with releasing snap modifiers).
- Because matching is exact, shrinking never happens while a snap combination is held.

### Screen lock
- When the shrink combination becomes active, the screen under the cursor is **locked**. While it stays held, the effective cursor position is clamped to that screen's bounds, so every edge — including edges shared with another monitor — acts as a real edge. If the physical cursor moves onto a neighbouring screen, it is interpreted as being at the edge of the locked screen.
- Releasing the combination unlocks: the window follows the real cursor (possibly onto the other screen) at full size. Pressing the combination again locks the screen the cursor is on now.

### Left / right shrink zones
- Depth measured from the clamped cursor: `t = clamp((zoneWidth − distanceFromEdge) / zoneWidth, 0, 1)`.
- Uniform scaling, aspect ratio preserved, from full size (t = 0) down to the configured **minimum width in points** (t = 1). Linear interpolation. The app's own minimum size may prevent further shrinking.
- Scaling is anchored at the grab point: the cursor keeps the same relative position inside the window.
- Size is always computed from the full (drag-start or remembered) size, so moving back out of the zone grows the window smoothly.
- Mouse-up inside the zone leaves the window shrunk.

### Remembered original size
- The original size of a shrunk window is kept in memory, keyed by window ID.
- When such a window is picked up with the shrink combination held (or the combination is pressed during its drag), the remembered size is used as the full size.
- Picked up without the combination, the window moves at its current (shrunk) size.
- The entry is forgotten when the window is dropped at full size with shrinking active.

### Bottom minimize zone
- The bottom band of the locked screen, **only between** the left and right shrink zones. In the bottom corners shrinking wins, no minimize.
- Entering it does not resize the window. An **overlay strip** (borderless, click-through, non-activating panel above all windows, on all Spaces) highlights that middle section of the bottom edge.
- Mouse-up inside: the window is first restored to its drag-start frame, then minimized (AX `kAXMinimizedAttribute`; own windows via `NSWindow.miniaturize`). Performed on the `WindowManipulator` serial queue after the last pending frame.
- Leaving the zone or releasing the combination before mouse-up cancels the minimize.
- Windows that cannot be minimized (attribute not settable): no strip, no action.
- No haptic feedback for now.

### Settings — Behaviour tab, "Screen Edges" card
| Setting | Default |
|---|---|
| Edge zone width | 120 pt |
| Minimum width | 400 pt |
| Bottom zone height | 40 pt |

No enable switches: the feature is enabled by assigning a modifier combination in the Keys tab (hint text in the card says so). Both edge shrink and bottom minimize are enabled/disabled together. New keys with defaults — no migration needed.

### Implementation outline
- `GridSnapper` — pure functions: zone detection (`none` / `shrink(side, t)` / `minimize`) and anchored scaled frame.
- `MouseInteractionHandler` — screen lock, per-drag shrink state, remembered-size map, minimize on mouse-up.
- `WindowManipulator` — minimize operation on the serial queue.
- New `EdgeZoneOverlay.swift` — the overlay strip panel.
- `GridConfigStore` / `PreferencesView` — new settings, "Screen Edges" card, shrink row in the Modifier Combinations card.

### Implementation additions (decided during Step 2)
- The shrink never goes below the "Minimum Window Size" grab filter (Behaviour tab) in either dimension — otherwise a shrunk window could not be picked up again. The effective minimum is therefore `max(minWidth, filterWidth, filterHeight × aspect)`.
- Modifier changes during a drag are applied immediately (on `flagsChanged`), without waiting for the next mouse move. This applies to snapping too, and ensures that releasing the shrink combination in the bottom zone hides the strip and cancels the minimize even if the mouse is not moved.

### Notes / possible follow-ups
- Window updates are applied at 10 Hz, like resizing today; shrinking may look slightly stepped. The rate could be increased during shrink if needed.
- Native title-bar drags (and bottom-minimize for them) could be considered later.
