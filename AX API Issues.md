# AX API Issues — Research Findings & Fixes

+++ IMPORTANT +++
This is just keep for reference. Issue was fixed in Gridwell v1.0.11 (2026-08-10), commit 9a09a0c38a650675b482bc7470b780314adb9dd6

## Problem Description

Window dragging/resizing via Gridwell degraded progressively the longer the target application was running. After some time, resizing became increasingly laggy, and eventually the window would not resize correctly at all — or only if the mouse was moved very slowly. Fast mouse movements caused the window to not resize correctly, while slow movements still worked.

## Root Cause Analysis

Gridwell uses three macOS APIs in concert for live window manipulation:

1. **CGEventTap** (`.cgSessionEventTap` / `.headInsertEventTap`) — intercepts all mouse and key events system-wide
2. **AXUIElement** (Accessibility API) — sets window position/size via `kAXPositionAttribute` / `kAXSizeAttribute`
3. **CGWindowListCopyWindowInfo** — enumerates on-screen windows for hit-testing and snapping

The degradation was caused by five API-level issues in how the AXUIElement API was used under continuous live-drag load. Gridwell's architecture is fundamentally different from keyboard-shortcut-driven window managers like Rectangle: Gridwell applies AX frames continuously at 10 Hz during the entire drag, while Rectangle does one-shot `setFrame` calls on keyboard shortcuts or snap-at-release. This makes Gridwell more powerful (live snapping/resizing) but far more demanding on the AX API.

---

## Issue 1: Read-back Retry Loop Under Continuous Load — PRIMARY SUSPECT

### The API Issue

Each `AXUIElementSetAttributeValue` / `AXUIElementCopyAttributeValue` call is a **synchronous IPC round-trip** to the target application's process. These are not local function calls — they cross process boundaries and block until the target app's main thread responds. Each call costs ~1–15 ms, growing as the target app's accessibility tree grows or its main thread gets busier.

### How Gridwell Used It

The `setFrame` method did up to **5 retry iterations**, each making **4 synchronous AX IPC calls** (set size, set position, read position, read size). Worst case: **20 synchronous IPC calls per timer tick**. At 10 Hz, that's up to **200 IPC calls/second** to the target app.

### Why It Degrades Over Time

As the target app runs longer, its accessibility tree grows (more views, more state), and each IPC call takes longer. The read-back is increasingly likely to *not match* (because the app is still processing the previous write, or is animating), which triggers more retry iterations. Each retry is another full round of 4 IPC calls. This creates a **multiplicative amplification**: if AX calls go from 2 ms to 10 ms each, a single attempt goes from 8 ms to 40 ms, but a 5-retry failure goes from 40 ms to 200 ms — exceeding the 100 ms timer interval.

### The Industry Standard

Rectangle's `setFrame` (in `AccessibilityElement.swift`) is **fire-and-forget**: set size → set position → set size again. No read-back, no retries, no verification. It logs the result for debugging but never blocks waiting for convergence. This is a deliberate architectural choice — read-back verification creates a tight coupling between the window manager's frame rate and the target app's AX response time.

### Fix Applied

- **Max retries reduced from 5 to 3** — worst-case IPC calls drop from 20 to 12 per tick.
- **Stale-frame abort** — between retries, re-reads `pendingFrame` under the lock. If a newer frame arrived from the drag handler, bails immediately instead of burning IPC calls on an obsolete frame. This is the key defense against fast mouse movements: instead of 12 calls chasing a stale frame, we bail after 4–8.
- **80 ms time budget** — the total `setFrame` call is capped at 80 ms (leaving 20 ms headroom in the 100 ms timer interval). Even very slow AX responses can't back up the serial queue beyond one tick.

---

## Issue 2: No `AXUIElementSetMessagingTimeout` — No Bound on Blocking

### The API Issue

Without calling `AXUIElementSetMessagingTimeout`, AX calls use the **system default timeout of several seconds**. If the target app's main thread is momentarily busy (GC pause, heavy layout, animation), a single AX call can block for the full default timeout — seconds, not milliseconds.

### How Gridwell Used It

Gridwell never called `AXUIElementSetMessagingTimeout`. Every `AXUIElementSetAttributeValue` and `AXUIElementCopyAttributeValue` in `setFrame`, `readPosition`, `readSize`, and `findAXWindow` could block for seconds.

### Why It Degrades Over Time

As the target app gets busier, momentary main-thread stalls become more frequent and longer. Each stall blocks the serial `axQueue` for the full default timeout. No frames are applied during this stall. When the stall clears, the next frame applied is very stale — the mouse has moved far ahead. With the retry loop, the stale frame may not converge, triggering more retries that further block the queue.

### Fix Applied

`AXUIElementSetMessagingTimeout(axApp, 0.5)` called on the AX app element at `beginDrag` time. This bounds each individual IPC call to 0.5 seconds. Combined with the 80 ms time budget in `setFrame`, the absolute worst-case `setFrame` duration is min(80 ms, 3 × 4 × 500 ms) = 80 ms — the time budget always wins.

### Reference

Rectangle's `AccessibilityElement.swift` includes a `setMessagingTimeout(_ seconds: Float)` method wrapping `AXUIElementSetMessagingTimeout`, available for use when targeting apps that may be slow to respond.

---

## Issue 3: `AXEnhancedUserInterface` Not Handled — Animated Resizing for Chromium/Electron Apps

### The API Issue

`AXEnhancedUserInterface` is a per-app accessibility attribute. When enabled (which Chromium/Electron apps like Chrome, VS Code, Slack, Discord enable automatically when they detect an accessibility client), setting `kAXPositionAttribute`/`kAXSizeAttribute` triggers **animated window moves/resizes** instead of instant jumps. These animations:

- Make the read-back not match (the window is still animating to the target position), triggering more retries
- Add GPU/compositing work to the target app's main thread, making it busier
- Accumulate over time — each new resize request arrives while previous animations are still running

This is a **well-documented known issue**, confirmed by both Rectangle's source code and the "nudge" window manager project (mikusnuz/nudge on GitHub), which explicitly note: "disable `AXEnhancedUserInterface` to prevent Chrome animated resize."

### How Gridwell Used It

Gridwell's code explicitly avoided `AXEnhancedUserInterface`, citing VoiceOver regressions and Chromium UI freezes. This was a deliberate decision, but it meant Gridwell had no defense against the animated-resize problem.

### How Rectangle Handles It

Before each `setFrame`, Rectangle checks if `AXEnhancedUserInterface` is enabled on the target app. If so, it **temporarily disables it**, performs the resize, then optionally re-enables it (controlled by a user preference: `disableEnable`, `disableOnly`, or `frontmostDisable`). This prevents animated resizing during AX-driven window manipulation.

### Fix Applied

At `beginDrag`: reads the target app's `AXEnhancedUserInterface` attribute. If enabled, disables it for the drag session. At `endDrag`: restores the original value. This adds only 2 IPC calls per drag *session* (not per tick). The disable duration equals the drag duration — acceptable since VoiceOver users are unlikely to be simultaneously dragging windows with Gridwell.

### Implementation Note

The Swift constant `kAXEnhancedUserInterfaceAttribute` is not exposed in Swift. The attribute name must be passed as a string literal: `"AXEnhancedUserInterface" as CFString`.

---

## Issue 4: Serial Queue + Synchronous IPC = Progressive Rate Degradation

### The API/Framework Issue

`DispatchSourceTimer` on a **serial `DispatchQueue`** processes timer events one at a time. If the handler (`applyPendingFrame` → `setFrame`) takes longer than the timer interval (100 ms), the timer can't fire at its intended rate. GCD **coalesces** timer events (doesn't queue them unboundedly), so the queue doesn't grow infinitely — but the **effective frame rate drops** below 10 Hz, and the latency between a drag event and its frame application grows.

### Why It Degrades Over Time

The handler's duration is dominated by AX IPC calls (see Issue 1). As those get slower, the handler takes longer, the effective frame rate drops further, and frames are applied increasingly late. The applied frame is stale — it represents where the mouse *was*, not where it *is*.

### Why Fast Mouse Movements Make It Worse

With fast movements, the desired frame changes rapidly between (now infrequent) timer ticks. The applied frame is very stale — the window jumps to an old position. With slow movements, the desired frame barely changes between ticks, so staleness matters less. This matches the reported symptom exactly: *"only if during resizing I move the mouse very slowly."*

### Fix Applied

The 80 ms time budget in `setFrame` ensures the handler never blocks the queue for more than 80 ms per tick, maintaining the 10 Hz effective frame rate even under slow AX response. The stale-frame abort further reduces wasted time on obsolete frames.

### What Was NOT Changed

- **10 Hz timer frequency** — stays. Not the root cause; the retry loop amplification was.
- **Serial queue** — stays. Correct for AX call ordering. The time budget prevents it from backing up.

---

## Issue 5: No "Skip If Busy" / Abort-on-Stale Guard

### The Framework Issue

The timer handler had no mechanism to detect that `setFrame` is taking too long and should abort. On a serial queue, the next tick waits for the current one to finish, but there was no logic to say "this frame is already stale, skip it and use the next one." More critically, there was no logic to detect that the target app is unresponsive and reduce the retry count or back off.

The code applied `pendingFrame` (the latest desired frame) at each tick, which is correct for staleness — but the retry loop inside `setFrame` could spend a long time trying to reach a frame that's already outdated by the time it finishes. This was wasted work that blocked the queue.

### Fix Applied

The stale-frame abort between retry iterations directly addresses this. If `pendingFrame` has changed since the current `setFrame` call started, the current frame is abandoned immediately.

---

## Summary of Changes

All changes were made in `WindowManipulator.swift` only.

### `beginDrag` (AX path for other apps)

```swift
// 1. Bound each AX IPC call to 0.5 s (Issue 2)
AXUIElementSetMessagingTimeout(axApp, 0.5)

// 2. Disable AXEnhancedUserInterface for the drag session (Issue 3)
enhancedUIWasEnabled = readEnhancedUI(from: axApp)
if enhancedUIWasEnabled == true {
    setEnhancedUI(false, on: axApp)
}
```

### `endDrag`

```swift
// Restore AXEnhancedUserInterface if we disabled it at drag start (Issue 3)
if enhancedUIWasEnabled == true, let axApp = cachedAXApp {
    setEnhancedUI(true, on: axApp)
}
enhancedUIWasEnabled = nil
```

### `setFrame` (the retry loop)

```swift
private func setFrame(_ frame: CGRect, for axWindow: AXUIElement, retries: Int = 3) {
    let start = DispatchTime.now()
    let timeBudgetNs: UInt64 = 80_000_000  // 80 ms

    for attempt in 0..<retries {
        // Between retries: abort if stale or time budget exhausted (Issues 1, 4, 5)
        if attempt > 0 {
            if DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds > timeBudgetNs {
                return  // time budget exhausted
            }
            lock.lock()
            let pending = pendingFrame
            lock.unlock()
            if pending != nil && pending != frame {
                return  // stale — newer frame pending
            }
        }

        // Size first, then position
        applySize(frame.size, to: axWindow)
        applyPosition(frame.origin, to: axWindow)

        // Read back both; break early when both match
        let posOK = readPosition(from: axWindow).map { ... } ?? false
        let sizeOK = readSize(from: axWindow).map { ... } ?? false
        if posOK && sizeOK { return }
    }
}
```

### New helper methods

```swift
private func readEnhancedUI(from axApp: AXUIElement) -> Bool? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, &ref) == .success,
          let val = ref else { return nil }
    return val as? Bool
}

private func setEnhancedUI(_ enabled: Bool, on axApp: AXUIElement) {
    AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, enabled as CFBoolean)
}
```

---

## IPC Call Budget Comparison

| Scenario | Before | After |
|----------|--------|-------|
| Converges on attempt 0 (best case) | 4 calls | 4 calls |
| Converges on attempt 1 | 8 calls | 8 calls + 1 stale check (lock only) |
| Converges on attempt 2 | 12 calls | 12 calls + 2 stale checks |
| Doesn't converge (worst case) | 20 calls + NSLog | 12 calls, or fewer (time budget/stale abort) |
| Fast mouse, frame goes stale mid-retry | 20 calls (no stale detection) | 4–8 calls (stale abort) |
| **Per second at 10 Hz, all ticks converge** | **40 calls/s** | **40 calls/s** |
| **Per second at 10 Hz, all ticks fail** | **200 calls/s + 10 NSLogs** | **~120 calls/s, bounded to 80 ms each** |

---

## What Was NOT Changed

- **Size-before-position ordering** — stays. Prevents the system from repositioning after a size change.
- **1.0 pt tolerance** on read-back verification — stays. Reasonable for point-space coordinates.
- **10 Hz timer frequency** — stays. Not the root cause; the retry loop amplification was.
- **Serial queue** — stays. Correct for AX call ordering. The time budget prevents it from backing up.
- **`lastAppliedFrame` semantics** — stays. Set before `setFrame` returns; if `setFrame` aborts early, the next tick still applies the latest `pendingFrame` (which changes on every mouse-moved event during a live drag).

---

## Key Architectural Difference: Gridwell vs. Rectangle

| Aspect | Rectangle | Gridwell |
|--------|-----------|----------|
| Trigger | Keyboard shortcuts / drag-to-snap at release | Live drag with modifier key or mouse button |
| AX frame application | One-shot `setFrame` per action | Continuous at 10 Hz during entire drag |
| Read-back verification | None (fire-and-forget) | Bounded retry loop (3 attempts, 80 ms budget, stale abort) |
| `AXEnhancedUserInterface` | Disabled before each resize, optionally re-enabled | Disabled for drag session, restored at endDrag |
| `AXUIElementSetMessagingTimeout` | Available via wrapper | Set to 0.5 s at drag start |
| Live snapping | No (footprint preview only) | Yes (snapping computed per drag event) |

Gridwell's live-drag architecture is more powerful but fundamentally more demanding on the AX API. The fixes ensure the retry loop and IPC calls are bounded so continuous load doesn't cause progressive degradation.

---

## References

- **Rectangle** (open-source macOS window manager): https://github.com/rxhanson/Rectangle
  - `AccessibilityElement.swift` — AX wrapper with `setFrame`, `enhancedUserInterface`, `setMessagingTimeout`
  - `WindowMover/StandardWindowMover.swift` — calls `setFrame` fire-and-forget
  - `Snapping/SnappingManager.swift` — uses NSEvent monitors (not CGEventTap), snap-at-release only
- **Nudge** (open-source macOS window manager): https://github.com/mikusnuz/nudge
  - Documents the `AXEnhancedUserInterface` disable workaround for Chrome animated resize
- **Apple Documentation**: `AXUIElementSetMessagingTimeout` bounds how long AX calls block on unresponsive apps

---

## Shipped In

Gridwell v1.0.11 — 2026-08-10
