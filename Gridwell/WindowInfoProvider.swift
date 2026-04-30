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

    // System-owned processes that produce chrome/utility windows, not user app windows.
    private static let systemOwners: Set<String> = [
        "Window Server", "Dock", "SystemUIServer", "Control Center",
        "WindowManager", "loginwindow", "NotificationCenter"
    ]

    func refresh() {
        let minWidth  = CGFloat(GridConfigStore.shared.minWindowWidth)
        let minHeight = CGFloat(GridConfigStore.shared.minWindowHeight)

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            NSLog("[WindowInfoProvider] Failed to retrieve window list")
            return
        }

        windows = rawList.compactMap { dict -> WindowInfo? in
            // Layer 0 = normal application windows. Higher layers are system chrome
            // (menu bar ~25, overlays 100+). Skip anything not at layer 0.
            let layer = dict[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { return nil }

            // Fully transparent windows are invisible; skip them.
            let alpha = dict[kCGWindowAlpha as String] as? Double ?? 0
            guard alpha > 0 else { return nil }

            guard
                let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                let pidRaw = dict[kCGWindowOwnerPID as String] as? Int32,
                let ownerName = dict[kCGWindowOwnerName as String] as? String,
                !ownerName.isEmpty,
                let boundsRef = dict[kCGWindowBounds as String],
                let frame = CGRect(dictionaryRepresentation: boundsRef as! CFDictionary)
            else { return nil }

            // Skip known system processes that produce non-interactive chrome.
            guard !Self.systemOwners.contains(ownerName) else { return nil }

            // Zero-size windows are invisible utility surfaces.
            guard frame.width > 0, frame.height > 0 else { return nil }

            // Skip accessory/panel windows that are too small (e.g. attached palette views).
            // minWidth/minHeight of 0 disables the filter for that dimension.
            guard frame.width >= minWidth, frame.height >= minHeight else { return nil }

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
        let zOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let zList = CGWindowListCopyWindowInfo(zOptions, kCGNullWindowID) as? [[String: Any]] {
            let candidateIDs = Set(candidates.map { $0.windowID })
            for entry in zList {
                // Apply the same phantom-window filters used in refresh().
                let entryLayer = entry[kCGWindowLayer as String] as? Int ?? -1
                let entryAlpha = entry[kCGWindowAlpha as String] as? Double ?? 0
                guard entryLayer == 0, entryAlpha > 0 else { continue }

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
