import AppKit
import CoreGraphics
import Foundation

struct WindowInfo {
    let windowID: CGWindowID
    let ownerName: String
    let windowName: String?   // nil when Screen Recording permission is not granted
    let frame: CGRect
    let layer: Int
}

class WindowInfoProvider {
    private(set) var windows: [WindowInfo] = []

    func refresh() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            NSLog("[WindowInfoProvider] Failed to retrieve window list")
            return
        }

        windows = rawList.compactMap { dict -> WindowInfo? in
            guard
                let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                let ownerName = dict[kCGWindowOwnerName as String] as? String,
                let boundsRef = dict[kCGWindowBounds as String],
                let frame = CGRect(dictionaryRepresentation: boundsRef as! CFDictionary),
                let layer = dict[kCGWindowLayer as String] as? Int
            else { return nil }

            return WindowInfo(
                windowID: windowID,
                ownerName: ownerName,
                windowName: dict[kCGWindowName as String] as? String,
                frame: frame,
                layer: layer
            )
        }

        NSLog("[WindowInfoProvider] Found %d on-screen windows", windows.count)
        for w in windows {
            let title = w.windowName.map { " — \"\($0)\"" } ?? ""
            NSLog("  [%@]%@ frame=%@ layer=%d", w.ownerName, title, NSStringFromRect(w.frame), w.layer)
        }
    }

    /// Returns the topmost on-screen window that contains the given point.
    /// - Parameter cgPoint: Position in CoreGraphics screen coordinates
    ///   (origin = top-left of primary display, Y increases downward).
    ///   This matches CGEvent.location directly — no conversion needed.
    func window(at cgPoint: CGPoint) -> WindowInfo? {
        // windows is already sorted front-to-back, so the first match is the topmost.
        return windows.first { $0.frame.contains(cgPoint) }
    }
}
