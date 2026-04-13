import AppKit
import CoreGraphics

class MouseInteractionHandler {

    // MARK: - State
    private let windowInfoProvider: WindowInfoProvider
    private let modifierKeyMonitor: ModifierKeyMonitor
    private let windowManipulator = WindowManipulator()
    private var activeWindow: WindowInfo?

    // Hard-coded target for Stage 3 testing.
    private let testFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // Retained pointer to self passed through the C callback via userInfo
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
            (1 << CGEventType.leftMouseUp.rawValue)

        // Retain self so the C callback can reach it via userInfo
        let retained = Unmanaged.passRetained(self)
        selfPtr = retained.toOpaque()

        // The callback is a C function — state is accessed via userInfo.
        // It runs on the main run loop (see CFRunLoopAddSource below), so
        // accessing MainActor-isolated properties is safe at runtime.
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let handler = Unmanaged<MouseInteractionHandler>.fromOpaque(userInfo).takeUnretainedValue()
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

    // MARK: - Event handling

    // Called on the main run loop thread.
    // Returns nil to suppress the event, or the original event to pass it through.
    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .leftMouseDown:    return handleMouseDown(event: event)
        case .leftMouseDragged: return handleMouseDragged(event: event)
        case .leftMouseUp:      return handleMouseUp(event: event)
        default:                return Unmanaged.passRetained(event)
        }
    }

    private func handleMouseDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let isFn = modifierKeyMonitor.isFnActive
        NSLog("[MouseInteractionHandler] leftMouseDown (FN=%@)", isFn ? "true" : "false")

        guard isFn else { return Unmanaged.passRetained(event) }

        let location = event.location  // CoreGraphics coords — matches window frame coords directly
        windowInfoProvider.refresh()

        if let window = windowInfoProvider.window(at: location) {
            activeWindow = window
            let title = window.windowName.map { " \"\($0)\"" } ?? ""
            NSLog("[MouseInteractionHandler] Drag started on [%@]%@ frame=%@",
                  window.ownerName, title, NSStringFromRect(window.frame))
        } else {
            NSLog("[MouseInteractionHandler] Mouse down at (%g, %g) — no window found", location.x, location.y)
        }

        return nil  // suppress: the click is ours, don't forward to the window below
    }

    private func handleMouseDragged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard activeWindow != nil else { return Unmanaged.passRetained(event) }
        let loc = event.location
        NSLog("[MouseInteractionHandler] Dragging at (%g, %g)", loc.x, loc.y)
        return nil  // suppress
    }

    private func handleMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let window = activeWindow else { return Unmanaged.passRetained(event) }
        let loc = event.location
        NSLog("[MouseInteractionHandler] Mouse up at (%g, %g) — drag ended", loc.x, loc.y)
        activeWindow = nil
        windowManipulator.move(window, to: testFrame)
        return nil  // suppress
    }
}
