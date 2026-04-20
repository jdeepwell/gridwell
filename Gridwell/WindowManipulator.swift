import AppKit

class WindowManipulator {

    private var cachedAXApp: AXUIElement?

    // Serial queue for AX calls and timer callbacks.
    private let axQueue = DispatchQueue(label: "com.gridwell.ax", qos: .userInteractive)

    // Protected by lock — written from the main thread, read from axQueue.
    private let lock = NSLock()
    private var cachedAXWindow: AXUIElement?
    private var ownWindow: NSWindow?        // set when the target is Gridwell's own window
    private var pendingFrame: CGRect?       // latest frame from drag events; nil = no update needed

    // Only accessed from axQueue.
    private var lastAppliedFrame: CGRect?
    private var updateTimer: DispatchSourceTimer?

    // MARK: - Drag session API

    /// Finds and caches the target window, then starts the 10 Hz update timer.
    /// When the target window belongs to Gridwell's own process, uses AppKit (NSWindow.setFrame)
    /// because AXUIElementSetAttributeValue cannot manipulate the calling app's own windows.
    /// AXEnhancedUserInterface is intentionally NOT set — disabling it causes VoiceOver regressions
    /// and Chromium UI freezes; a size-first + read-back retry loop is used instead.
    func beginDrag(for windowInfo: WindowInfo) -> Bool {
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        if windowInfo.pid == ownPID {
            // Own-process window: AX API will crash — use AppKit instead.
            // CGWindowID == NSWindow.windowNumber, so the match is exact.
            let matched = NSApp.windows.first { $0.windowNumber == Int(windowInfo.windowID) }
            lock.lock()
            ownWindow      = matched
            cachedAXWindow = nil
            pendingFrame   = nil
            lock.unlock()
            cachedAXApp = nil
            startUpdateTimer(startFrame: windowInfo.frame)
            if matched == nil {
                NSLog("[WindowManipulator] beginDrag: own-process window not found for [%@] frame=%@",
                      windowInfo.ownerName, NSStringFromRect(windowInfo.frame))
            }
            return matched != nil
        }

        // AX path for other apps.
        lock.lock()
        ownWindow = nil
        lock.unlock()

        let axApp = AXUIElementCreateApplication(windowInfo.pid)
        cachedAXApp = axApp
        let axWindow = findAXWindow(for: windowInfo, in: axApp)

        lock.lock()
        cachedAXWindow = axWindow
        pendingFrame   = nil
        lock.unlock()

        startUpdateTimer(startFrame: windowInfo.frame)

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
    /// For own-process windows both AX lookups are skipped (cachedAXWindow/App are nil).
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
        ownWindow      = nil
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
        let ownWin   = ownWindow
        let axWindow = cachedAXWindow
        let newFrame = pendingFrame
        lock.unlock()

        guard let newFrame, newFrame != lastAppliedFrame else { return }
        lastAppliedFrame = newFrame

        if let ownWin {
            // Own-process window: NSWindow must be moved on the main thread.
            let nsFrame = cgToAppKit(newFrame)
            DispatchQueue.main.async { ownWin.setFrame(nsFrame, display: true) }
        } else if let axWindow {
            setFrame(newFrame, for: axWindow)
        }
    }

    // MARK: - Private helpers

    private func startUpdateTimer(startFrame: CGRect) {
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
    }

    /// Converts a CoreGraphics rect (origin top-left of primary screen, Y down) to an AppKit rect
    /// (origin bottom-left of primary screen, Y up) for use with NSWindow.setFrame.
    private func cgToAppKit(_ cgRect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(
            x: cgRect.minX,
            y: primaryHeight - cgRect.maxY,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    /// Applies size then position with a read-back retry loop.
    /// Size-before-position ordering prevents the system from repositioning the window after a
    /// size change overwrites an earlier position set. The retry loop handles apps that animate
    /// or clamp geometry — industry-standard approach used by Rectangle, Moom, etc.
    /// Both position AND size are verified before returning; verifying only position would miss
    /// cases where the size update lags (e.g. when crossing screen boundaries).
    private func setFrame(_ frame: CGRect, for axWindow: AXUIElement, retries: Int = 5) {
        for attempt in 0..<retries {
            // Size first, then position — prevents system from repositioning after size change.
            applySize(frame.size, to: axWindow)
            applyPosition(frame.origin, to: axWindow)

            // Read back both position and size; break early only when both match.
            let posOK = readPosition(from: axWindow).map {
                abs($0.x - frame.origin.x) < 1.0 && abs($0.y - frame.origin.y) < 1.0
            } ?? false
            let sizeOK = readSize(from: axWindow).map {
                abs($0.width - frame.size.width) < 1.0 && abs($0.height - frame.size.height) < 1.0
            } ?? false

            if posOK && sizeOK {
                if attempt > 0 {
                    NSLog("[WindowManipulator] setFrame converged after %d retries", attempt)
                }
                return
            }
        }
        NSLog("[WindowManipulator] setFrame: frame did not converge after %d attempts", retries)
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

    private func readSize(from axWindow: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &ref) == .success,
              let val = ref else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(val as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Returns true when the AX window's current position is within 2 pts of the expected frame origin.
    private func matches(_ axWindow: AXUIElement, frame: CGRect) -> Bool {
        guard let pos = readPosition(from: axWindow) else { return false }
        return abs(pos.x - frame.origin.x) < 2 && abs(pos.y - frame.origin.y) < 2
    }
}
