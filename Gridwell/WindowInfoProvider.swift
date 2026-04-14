import AppKit
import CoreGraphics
import Foundation

struct WindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
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
                let pidRaw = dict[kCGWindowOwnerPID as String] as? Int32,
                let ownerName = dict[kCGWindowOwnerName as String] as? String,
                let boundsRef = dict[kCGWindowBounds as String],
                let frame = CGRect(dictionaryRepresentation: boundsRef as! CFDictionary),
                let layer = dict[kCGWindowLayer as String] as? Int
            else { return nil }

            return WindowInfo(
                windowID: windowID,
                pid: pidRaw,
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
        let candidates = windows.filter { $0.frame.contains(cgPoint) }
        guard !candidates.isEmpty else { return nil }

        // Fast path: no overlap, no ambiguity.
        if candidates.count == 1 { return candidates.first }

        // Multiple windows overlap the click point.
        // CGWindowListCopyWindowInfo does NOT guarantee ordering within the same layer,
        // so we cannot rely on list position alone. Instead, re-query the window server for
        // the current front-to-back order and return whichever candidate appears first.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let zList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            let candidateIDs = Set(candidates.map { $0.windowID })
            for entry in zList {
                guard let wid = entry[kCGWindowNumber as String] as? CGWindowID,
                      candidateIDs.contains(wid),
                      let match = candidates.first(where: { $0.windowID == wid })
                else { continue }
                NSLog("[WindowInfoProvider] z-ordered pick: [%@] (topmost of %d overlapping windows)",
                      match.ownerName, candidates.count)
                return match
            }
        }

        // Fallback: return the first candidate from the last refresh().
        return candidates.first
    }
}
