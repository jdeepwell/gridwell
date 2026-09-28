import AppKit
import CoreGraphics

class MouseInteractionHandler {

    // MARK: - Dependencies
    private let windowInfoProvider: WindowInfoProvider
    private let modifierKeyMonitor: ModifierKeyMonitor
    private let windowManipulator = WindowManipulator()
    private let gridStore = GridConfigStore.shared

    // MARK: - Drag session state
    private enum DragSource { case modifierKey, mouseButton }
    private var dragSource: DragSource? = nil   // non-nil while a drag is in progress
    private var activeWindow: WindowInfo?        // window being dragged (nil if click landed on nothing)
    private var dragStartMousePos  = CGPoint.zero
    private var dragStartWindowFrame = CGRect.zero
    private var dragZone: DragZone = .move
    private var otherWindows: [WindowInfo] = []

    // MARK: - Edge shrink state
    private var grabFraction = CGPoint.zero      // cursor position inside the window at drag start, 0…1 per axis
    private var fullSize = CGSize.zero           // size edge shrink scales down from
    private var shrinkUsed = false               // edge shrink was active at some point in this drag
    private var lockedScreen: CGRect?            // CG frame of the locked screen; non-nil while edge shrink is active
    private var lastShrinkSize = CGSize.zero     // size applied by the latest edge shrink update
    private var inMinimizeZone = false
    private var shrunkSizes: [CGWindowID: CGSize] = [:]   // original sizes of windows left shrunk
    private let edgeZoneOverlay = EdgeZoneOverlay()

    // MARK: - Event tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selfPtr: UnsafeMutableRawPointer?

    // MARK: - Init
    init(windowInfoProvider: WindowInfoProvider, modifierKeyMonitor: ModifierKeyMonitor) {
        self.windowInfoProvider = windowInfoProvider
        self.modifierKeyMonitor = modifierKeyMonitor
    }

    // MARK: - Lifecycle
    func start() {
        let mouseMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)     |
            (1 << CGEventType.leftMouseDragged.rawValue)  |
            (1 << CGEventType.leftMouseUp.rawValue)       |
            (1 << CGEventType.otherMouseDown.rawValue)    |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)
        let keyMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)      |
            (1 << CGEventType.keyDown.rawValue)           |
            (1 << CGEventType.keyUp.rawValue)
        let eventMask: CGEventMask = mouseMask | keyMask

        let retained = Unmanaged.passRetained(self)
        selfPtr = retained.toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let handler = Unmanaged<MouseInteractionHandler>.fromOpaque(userInfo).takeUnretainedValue()
            // Re-enable immediately if the system disabled the tap.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                handler.reenableTap()
                return nil
            }
            return handler.handleCGEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            NSLog("[MouseInteractionHandler] Failed to create event tap — Accessibility permission may be missing")
            retained.release()
            selfPtr = nil
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        NSLog("[MouseInteractionHandler] Event tap started — triggers: modifier key or middle mouse button")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let ptr = selfPtr {
            Unmanaged<MouseInteractionHandler>.fromOpaque(ptr).release()
            selfPtr = nil
        }
    }

    deinit { stop() }

    private func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[MouseInteractionHandler] Event tap re-enabled after timeout")
    }

    // MARK: - Event routing

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .leftMouseDown:     return handleMouseDown(event: event)
        case .leftMouseDragged:  return handleMouseDragged(event: event)
        case .leftMouseUp:       return handleMouseUp(event: event)
        case .otherMouseDown:    return handleOtherMouseDown(event: event)
        case .otherMouseDragged: return handleOtherMouseDragged(event: event)
        case .otherMouseUp:      return handleOtherMouseUp(event: event)
        case .flagsChanged:      return handleFlagsChanged(event: event)
        case .keyDown:           return handleKeyDown(event: event)
        case .keyUp:             return handleKeyUp(event: event)
        default:                 return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Modifier / key events

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        modifierKeyMonitor.handleFlagsChanged(event)
        // Apply modifier changes mid-drag immediately, without waiting for the next mouse move.
        if dragSource != nil { _ = applyDragUpdate(event: event) }
        return Unmanaged.passRetained(event)    // modifier changes are never suppressed
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        modifierKeyMonitor.handleKeyDown(keyCode: keyCode)

        // Suppress if this keyDown is the non-modifier component of the trigger shortcut
        // AND the required modifier keys are currently held.
        let shortcut = gridStore.triggerShortcut
        guard let requiredKey = shortcut.keyCode, keyCode == requiredKey else {
            return Unmanaged.passRetained(event)
        }
        let eventFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        guard eventFlags.intersection(TriggerShortcut.relevantModifiers).contains(shortcut.modifierFlags) else {
            return Unmanaged.passRetained(event)
        }
        return nil  // suppress: prevent the key from reaching any app
    }

    private func handleKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        modifierKeyMonitor.handleKeyUp(keyCode: keyCode)

        // Suppress the keyUp if its keyDown was suppressed (same key code is sufficient).
        let shortcut = gridStore.triggerShortcut
        guard let requiredKey = shortcut.keyCode, keyCode == requiredKey else {
            return Unmanaged.passRetained(event)
        }
        return nil  // suppress
    }

    // MARK: - Modifier key mouse handlers

    private func handleMouseDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard modifierKeyMonitor.isTriggerActive else { return Unmanaged.passRetained(event) }
        guard dragSource == nil else { return nil }
        dragSource = .modifierKey
        startDragSession(at: event.location)
        return nil
    }

    private func handleMouseDragged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard dragSource == .modifierKey else { return Unmanaged.passRetained(event) }
        return applyDragUpdate(event: event)
    }

    private func handleMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard dragSource == .modifierKey else { return Unmanaged.passRetained(event) }
        endDragSession()
        return nil
    }

    // MARK: - Middle mouse button handlers

    private func handleOtherMouseDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let configured = gridStore.mouseButtonTrigger else { return Unmanaged.passRetained(event) }
        guard event.getIntegerValueField(.mouseEventButtonNumber) == configured else {
            return Unmanaged.passRetained(event)
        }
        if isMouseButtonExcluded(at: event.location) { return Unmanaged.passRetained(event) }
        guard dragSource == nil else { return nil }
        dragSource = .mouseButton
        startDragSession(at: event.location)
        return nil
    }

    /// Returns true if the topmost window at `location` belongs to an app in the exclusion list.
    private func isMouseButtonExcluded(at location: CGPoint) -> Bool {
        guard !gridStore.mouseButtonExcludedApps.isEmpty else { return false }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for dict in list {
            guard (dict[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard (dict[kCGWindowAlpha as String] as? Double ?? 0) > 0 else { continue }
            guard
                let pidRaw = dict[kCGWindowOwnerPID as String] as? Int32,
                let boundsRef = dict[kCGWindowBounds as String],
                let frame = CGRect(dictionaryRepresentation: boundsRef as! CFDictionary),
                frame.contains(location)
            else { continue }
            guard let bundleID = NSRunningApplication(processIdentifier: pidRaw)?.bundleIdentifier else {
                continue
            }
            return gridStore.isMouseButtonExcluded(bundleID: bundleID)
        }
        return false
    }

    private func handleOtherMouseDragged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard dragSource == .mouseButton else { return Unmanaged.passRetained(event) }
        return applyDragUpdate(event: event)
    }

    private func handleOtherMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let configured = gridStore.mouseButtonTrigger else { return Unmanaged.passRetained(event) }
        guard event.getIntegerValueField(.mouseEventButtonNumber) == configured else {
            return Unmanaged.passRetained(event)
        }
        guard dragSource == .mouseButton else { return Unmanaged.passRetained(event) }
        endDragSession()
        return nil
    }

    // MARK: - Shared drag session helpers

    private func startDragSession(at location: CGPoint) {
        windowInfoProvider.refresh()

        guard let window = windowInfoProvider.window(at: location) else {
            NSLog("[MouseInteractionHandler] Down at (%g, %g) — no window found", location.x, location.y)
            return
        }

        activeWindow         = window
        dragStartMousePos    = location
        dragStartWindowFrame = window.frame
        dragZone             = GridSnapper.dragZone(
            at: location, in: window.frame,
            borderPercent: CGFloat(gridStore.resizeBorderPercent / 100.0),
            borderMinPixels: CGFloat(gridStore.resizeBorderMinPixels)
        )
        otherWindows = windowInfoProvider.windows.filter { $0.windowID != window.windowID }

        let frame = window.frame
        grabFraction = CGPoint(x: frame.width  > 0 ? (location.x - frame.minX) / frame.width  : 0.5,
                               y: frame.height > 0 ? (location.y - frame.minY) / frame.height : 0.5)
        fullSize       = shrunkSizes[window.windowID] ?? frame.size
        shrinkUsed     = false
        lockedScreen   = nil
        inMinimizeZone = false
        windowManipulator.beginDrag(for: window)

        if gridStore.raiseWindowOnDrag {
            windowManipulator.raiseWindow(pid: window.pid)
        }

        let zoneLabel: String
        switch dragZone {
        case .move:              zoneLabel = "move"
        case .resize(let edges): zoneLabel = "resize(rawValue:\(edges.rawValue))"
        }
        let title = window.windowName.map { " \"\($0)\"" } ?? ""
        NSLog("[MouseInteractionHandler] Drag started on [%@]%@ zone=%@ frame=%@",
              window.ownerName, title, zoneLabel, NSStringFromRect(window.frame))
    }

    private func applyDragUpdate(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard activeWindow != nil else { return nil }

        let location = event.location
        // Exact match: a feature is active only while exactly its combination is held.
        let held = ModifierCombination(cgEventFlags: event.flags)

        if case .move = dragZone, gridStore.modifiers(for: .edgeShrink).isActive(held: held) {
            applyEdgeShrink(at: location)
            return nil
        }
        lockedScreen = nil
        setMinimizeZone(nil)

        let candidate: CGRect
        if shrinkUsed {
            // Edge shrink was released: back to full size at the real cursor position.
            candidate = GridSnapper.frame(size: fullSize, anchoredAt: location, grabFraction: grabFraction)
        } else {
            let delta = CGPoint(
                x: location.x - dragStartMousePos.x,
                y: location.y - dragStartMousePos.y
            )
            candidate = GridSnapper.candidateFrame(
                startFrame: dragStartWindowFrame,
                delta: delta,
                zone: dragZone
            )
        }

        let snapMode: SnapMode
        let snapWindows: [WindowInfo]
        if gridStore.modifiers(for: .appWindowSnap).isActive(held: held) {
            snapMode = .windows
            snapWindows = otherWindows.filter { $0.pid == activeWindow?.pid }
        } else if gridStore.modifiers(for: .windowSnap).isActive(held: held) {
            snapMode = .windows
            snapWindows = otherWindows
        } else if gridStore.modifiers(for: .gridSnap).isActive(held: held) {
            snapMode = .grid
            snapWindows = []
        } else {
            snapMode = .none
            snapWindows = []
        }

        let snapped = GridSnapper.snap(
            candidate: candidate,
            otherWindows: snapWindows,
            zone: dragZone,
            gridStore: gridStore,
            snapMode: snapMode,
            cursorLocation: location
        )

        windowManipulator.updateDrag(to: snapped)
        return nil
    }

    /// Edge shrink: the cursor is clamped to the screen locked when the shrink combination became
    /// active, so edges shared with another screen behave like outer edges. The window scales around
    /// the grab point in the left/right zones and keeps its full size in the bottom minimize zone.
    private func applyEdgeShrink(at location: CGPoint) {
        if lockedScreen == nil {
            guard let screen = GridSnapper.containingScreen(for: location) else { return }
            lockedScreen = GridSnapper.cgFrame(of: screen)
            shrinkUsed = true
        }
        guard let screen = lockedScreen else { return }

        let point      = GridSnapper.clamp(location, to: screen)
        let zoneWidth  = CGFloat(gridStore.edgeZoneWidth)
        let zoneHeight = CGFloat(gridStore.bottomZoneHeight)
        let zone = GridSnapper.edgeZone(at: point, in: screen, zoneWidth: zoneWidth, bottomHeight: zoneHeight)

        var size = fullSize
        if case .shrink(let t) = zone {
            size = GridSnapper.shrunkSize(
                fullSize: fullSize, t: t,
                minWidth: CGFloat(gridStore.edgeShrinkMinWidth),
                floorSize: CGSize(width: gridStore.minWindowWidth, height: gridStore.minWindowHeight)
            )
        }
        lastShrinkSize = size

        if zone == .minimize && windowManipulator.canMinimize {
            setMinimizeZone(GridSnapper.minimizeZoneRect(in: screen, zoneWidth: zoneWidth, bottomHeight: zoneHeight))
        } else {
            setMinimizeZone(nil)
        }

        windowManipulator.updateDrag(to: GridSnapper.frame(size: size, anchoredAt: point, grabFraction: grabFraction))
    }

    /// Shows the minimize strip over `rect` (CG coords), or hides it when nil.
    private func setMinimizeZone(_ rect: CGRect?) {
        inMinimizeZone = rect != nil
        if let rect {
            edgeZoneOverlay.show(at: rect)
        } else {
            edgeZoneOverlay.hide()
        }
    }

    private func endDragSession() {
        let minimize = inMinimizeZone && activeWindow != nil
        NSLog("[MouseInteractionHandler] Drag ended%@", minimize ? " — minimizing" : "")

        // Remember the full size of a window left shrunk; forget it once it is back at full size.
        // A minimized window is restored to its drag-start frame, so its entry stays as it was.
        if let window = activeWindow, shrinkUsed, !minimize {
            if lockedScreen != nil && lastShrinkSize != fullSize {
                shrunkSizes[window.windowID] = fullSize
            } else {
                shrunkSizes[window.windowID] = nil
            }
        }

        setMinimizeZone(nil)
        lockedScreen = nil
        shrinkUsed   = false
        dragSource   = nil
        activeWindow = nil
        otherWindows = []
        windowManipulator.endDrag(minimizeRestoring: minimize ? dragStartWindowFrame : nil)
    }
}
