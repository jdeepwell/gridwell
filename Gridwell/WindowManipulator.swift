import AppKit

class WindowManipulator {

    /// Moves and resizes the given window to `frame` using the Accessibility API.
    /// Coordinates are in CoreGraphics space (origin top-left of primary screen, Y down),
    /// matching the values stored in `WindowInfo.frame`.
    func move(_ windowInfo: WindowInfo, to frame: CGRect) {
        let axApp = AXUIElementCreateApplication(windowInfo.pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            NSLog("[WindowManipulator] Failed to get AX windows for pid %d (%@)", windowInfo.pid, windowInfo.ownerName)
            return
        }

        // Find the AX window whose position matches the stored CG frame.
        guard let axWindow = axWindows.first(where: { matches($0, frame: windowInfo.frame) }) else {
            NSLog("[WindowManipulator] Could not match AX window for [%@] frame=%@",
                  windowInfo.ownerName, NSStringFromRect(windowInfo.frame))
            return
        }

        // Apply new position.
        var newOrigin = frame.origin
        if let posValue = AXValueCreate(.cgPoint, &newOrigin) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
        }

        // Apply new size.
        var newSize = frame.size
        if let sizeValue = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }

        NSLog("[WindowManipulator] Moved [%@] to %@", windowInfo.ownerName, NSStringFromRect(frame))
    }

    // MARK: - Private helpers

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
