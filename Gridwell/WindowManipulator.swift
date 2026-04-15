import AppKit

class WindowManipulator {

    private var cachedAXApp: AXUIElement?

    // Serial queue for AX calls and timer callbacks.
    private let axQueue = DispatchQueue(label: "com.gridwell.ax", qos: .userInteractive)

    // Protected by lock — written from the main thread, read from axQueue.
    private let lock = NSLock()
    private var cachedAXWindow: AXUIElement?
    private var pendingFrame: CGRect?   // latest frame from drag events; nil = no update needed

    // Only accessed from axQueue.
    private var lastAppliedFrame: CGRect?
    private var updateTimer: DispatchSourceTimer?
    // When both position and size change we split the work across two ticks:
    // tick 1 applies position, tick 2 applies size (once the frame has settled).
    // This prevents applyPosition from reverting a size change applied in the same tick.
    private var positionAppliedFor: CGRect?

    // MARK: - Drag session API

    /// Finds and caches the AX window for `windowInfo`, then starts the 10 Hz update timer.
    func beginDrag(for windowInfo: WindowInfo) -> Bool {
        let axApp = AXUIElementCreateApplication(windowInfo.pid)
        cachedAXApp = axApp
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        let axWindow = findAXWindow(for: windowInfo, in: axApp)

        lock.lock()
        cachedAXWindow = axWindow
        pendingFrame   = nil
        lock.unlock()

        let startFrame = windowInfo.frame
        axQueue.async { [weak self] in
            guard let self else { return }
            self.lastAppliedFrame = startFrame

            let timer = DispatchSource.makeTimerSource(queue: self.axQueue)
            // First tick after 100 ms so we never fire before the first drag event arrives.
            timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.applyPendingFrame() }
            timer.resume()
            self.updateTimer = timer
        }

        if axWindow == nil {
            NSLog("[WindowManipulator] beginDrag: could not find AX window for [%@] frame=%@",
                  windowInfo.ownerName, NSStringFromRect(windowInfo.frame))
        }
        return axWindow != nil
    }

    /// Raises the target window to the front using complementary approaches:
    /// - Option B: sets kAXMainAttribute on the specific AX window (raises it within its app).
    /// - Option A: sets kAXFrontmostAttribute on the app AX element and activates via
    ///   NSRunningApplication, which together reliably foreground apps that are not currently active.
    /// Must be called after beginDrag so that cachedAXWindow / cachedAXApp are already populated.
    func raiseWindow(pid: pid_t) {
        lock.lock()
        let axWindow = cachedAXWindow
        lock.unlock()

        if let axWindow {
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        if let axApp = cachedAXApp {
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Stores the latest desired frame. Cheap — just a locked write; the timer does the AX work.
    func updateDrag(to newFrame: CGRect) {
        lock.lock()
        pendingFrame = newFrame
        lock.unlock()
    }

    /// Stops the timer, clears state, and ends the enhanced-UI session.
    func endDrag() {
        lock.lock()
        cachedAXWindow = nil
        pendingFrame   = nil
        lock.unlock()

        if let axApp = cachedAXApp {
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        cachedAXApp = nil

        axQueue.async { [weak self] in
            guard let self else { return }
            self.updateTimer?.cancel()
            self.updateTimer = nil
            self.lastAppliedFrame   = nil
            self.positionAppliedFor = nil
        }
    }

    // MARK: - Timer callback (always on axQueue, 10 Hz)

    private func applyPendingFrame() {
        lock.lock()
        let axWindow = cachedAXWindow
        let newFrame = pendingFrame
        lock.unlock()

        guard let axWindow, let newFrame else {
            positionAppliedFor = nil
            return
        }

        // Tick 2: position was applied for this exact frame last tick — now apply size.
        if positionAppliedFor == newFrame {
            applySize(newFrame.size, to: axWindow)
            lastAppliedFrame   = newFrame
            positionAppliedFor = nil
            return
        }
        positionAppliedFor = nil

        let prev = lastAppliedFrame
        guard newFrame != prev else { return }

        let posChanged  = newFrame.origin != prev?.origin
        let sizeChanged = newFrame.size   != prev?.size

        if posChanged && sizeChanged {
            // Tick 1: apply position now; size follows next tick once the frame settles.
            applyPosition(newFrame.origin, to: axWindow)
            positionAppliedFor = newFrame   // lastAppliedFrame intentionally not updated yet
        } else if posChanged {
            applyPosition(newFrame.origin, to: axWindow)
            lastAppliedFrame = newFrame
        } else if sizeChanged {
            applySize(newFrame.size, to: axWindow)
            lastAppliedFrame = newFrame
        }
    }

    // MARK: - Private

    private func findAXWindow(for windowInfo: WindowInfo, in axApp: AXUIElement) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            NSLog("[WindowManipulator] Failed to get AX windows for pid %d (%@)",
                  windowInfo.pid, windowInfo.ownerName)
            return nil
        }
        return axWindows.first(where: { matches($0, frame: windowInfo.frame) })
    }

    private func applyPosition(_ origin: CGPoint, to axWindow: AXUIElement) {
        var o = origin
        if let v = AXValueCreate(.cgPoint, &o) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, v)
        }
    }

    private func applySize(_ size: CGSize, to axWindow: AXUIElement) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, v)
        }
    }

    /// Returns true when the AX window's current position is within 2 pts of the expected frame origin.
    private func matches(_ axWindow: AXUIElement, frame: CGRect) -> Bool {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
              let posValue = posRef else { return false }
        var pos = CGPoint.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos) else { return false }
        return abs(pos.x - frame.origin.x) < 2 && abs(pos.y - frame.origin.y) < 2
    }
}
