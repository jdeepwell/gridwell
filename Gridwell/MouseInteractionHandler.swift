import AppKit
import CoreGraphics

class MouseInteractionHandler {

    // MARK: - Dependencies
    private let windowInfoProvider: WindowInfoProvider
    private let modifierKeyMonitor: ModifierKeyMonitor
    private let windowManipulator = WindowManipulator()
    private let gridStore = GridConfigStore.shared

    // MARK: - Drag session state
    private var isTracking = false          // true while FN + left mouse button is held
    private var activeWindow: WindowInfo?   // window being dragged (nil if click landed on nothing)
    private var dragStartMousePos  = CGPoint.zero
    private var dragStartWindowFrame = CGRect.zero
    private var dragZone: DragZone = .move
    private var otherWindows: [WindowInfo] = []

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
        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)    |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)      |
            (1 << CGEventType.flagsChanged.rawValue)     |
            (1 << CGEventType.keyDown.rawValue)          |
            (1 << CGEventType.keyUp.rawValue)

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

        NSLog("[MouseInteractionHandler] Event tap started — trigger: FN + left mouse button")
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
        case .leftMouseDown:    return handleMouseDown(event: event)
        case .leftMouseDragged: return handleMouseDragged(event: event)
        case .leftMouseUp:      return handleMouseUp(event: event)
        case .flagsChanged:     return handleFlagsChanged(event: event)
        case .keyDown:          return handleKeyDown(event: event)
        case .keyUp:            return handleKeyUp(event: event)
        default:                return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Modifier / key events

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        modifierKeyMonitor.handleFlagsChanged(event)
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

    // MARK: - Mouse down

    private func handleMouseDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard modifierKeyMonitor.isTriggerActive else { return Unmanaged.passRetained(event) }

        isTracking = true
        let location = event.location
        windowInfoProvider.refresh()

        guard let window = windowInfoProvider.window(at: location) else {
            NSLog("[MouseInteractionHandler] Mouse down at (%g, %g) — no window found", location.x, location.y)
            return nil  // FN is held: suppress the click even with no target window
        }

        activeWindow       = window
        dragStartMousePos  = location
        dragStartWindowFrame = window.frame
        dragZone           = GridSnapper.dragZone(at: location, in: window.frame)
        otherWindows       = windowInfoProvider.windows.filter { $0.windowID != window.windowID }
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

        return nil
    }

    // MARK: - Mouse dragged

    private func handleMouseDragged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isTracking else { return Unmanaged.passRetained(event) }
        guard activeWindow != nil else { return nil }   // tracked but no window — just suppress

        let location = event.location
        let delta = CGPoint(
            x: location.x - dragStartMousePos.x,
            y: location.y - dragStartMousePos.y
        )

        let candidate = GridSnapper.candidateFrame(
            startFrame: dragStartWindowFrame,
            delta: delta,
            zone: dragZone
        )

        let snapMode: SnapMode
        let flags = event.flags
        if flags.contains(gridStore.windowSnapKey.cgEventFlag) {
            snapMode = .windows
        } else if flags.contains(gridStore.gridSnapKey.cgEventFlag) {
            snapMode = .grid
        } else {
            snapMode = .none
        }

        let snapped = GridSnapper.snap(
            candidate: candidate,
            otherWindows: otherWindows,
            zone: dragZone,
            gridStore: gridStore,
            snapMode: snapMode,
            cursorLocation: location
        )

        windowManipulator.updateDrag(to: snapped)
        return nil
    }

    // MARK: - Mouse up

    private func handleMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isTracking else { return Unmanaged.passRetained(event) }

        NSLog("[MouseInteractionHandler] Drag ended")
        isTracking   = false
        activeWindow = nil
        otherWindows = []
        windowManipulator.endDrag()
        return nil
    }
}
