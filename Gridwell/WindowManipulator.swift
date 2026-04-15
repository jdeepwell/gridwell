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

    // MARK: - Drag session API

    /// Finds and caches the AX window for `windowInfo`, then starts the 10 Hz update timer.
    /// AXEnhancedUserInterface is intentionally NOT set — disabling it causes VoiceOver regressions
    /// and Chromium UI freezes; a size-first + read-back retry loop is used instead.
    func beginDrag(for windowInfo: WindowInfo) -> Bool {
        let axApp = AXUIElementCreateApplication(windowInfo.pid)
        cachedAXApp = axApp
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
    /// - sets kAXMainAttribute on the specific AX window (raises it within its app).
    /// - sets kAXFrontmostAttribute on the app AX element and activates via
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

    /// Stops the timer and clears all drag state.
    func endDrag() {
        lock.lock()
        cachedAXWindow = nil
        pendingFrame   = nil
        lock.unlock()

        cachedAXApp = nil

        axQueue.async { [weak self] in
            guard let self else { return }
            self.updateTimer?.cancel()
            self.updateTimer = nil
            self.lastAppliedFrame = nil
        }
    }

    // MARK: - Timer callback (always on axQueue, 10 Hz)

    private func applyPendingFrame() {
        lock.lock()
        let axWindow = cachedAXWindow
        let newFrame = pendingFrame
        lock.unlock()

        guard let axWindow, let newFrame, newFrame != lastAppliedFrame else { return }

        setFrame(newFrame, for: axWindow)
        lastAppliedFrame = newFrame
    }

    // MARK: - Private

    /// Applies size then position with a read-back retry loop.
    /// Size-before-position ordering prevents the system from repositioning the window after a
    /// size change overwrites an earlier position set. The retry loop handles apps that animate
    /// or clamp geometry — industry-standard approach used by Rectangle, Moom, etc.
    private func setFrame(_ frame: CGRect, for axWindow: AXUIElement, retries: Int = 5) {
        for attempt in 0..<retries {
            // Size first, then position — prevents system from repositioning after size change.
            applySize(frame.size, to: axWindow)
            applyPosition(frame.origin, to: axWindow)

            // Read back position; break early if it matches.
            if let actual = readPosition(from: axWindow),
               abs(actual.x - frame.origin.x) < 1.0 && abs(actual.y - frame.origin.y) < 1.0 {
                if attempt > 0 {
                    NSLog("[WindowManipulator] setFrame converged after %d retries", attempt)
                }
                return
            }
        }
        NSLog("[WindowManipulator] setFrame: position did not converge after %d attempts", retries)
    }

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

    private func readPosition(from axWindow: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &ref) == .success,
              let val = ref else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(val as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// Returns true when the AX window's current position is within 2 pts of the expected frame origin.
    private func matches(_ axWindow: AXUIElement, frame: CGRect) -> Bool {
        guard let pos = readPosition(from: axWindow) else { return false }
        return abs(pos.x - frame.origin.x) < 2 && abs(pos.y - frame.origin.y) < 2
    }
}
