import AppKit
import CoreGraphics

// MARK: - DragZone

enum DragZone {
    case move
    case resize(ResizeEdges)
}

// MARK: - ResizeEdges

struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left   = ResizeEdges(rawValue: 1 << 0)
    static let right  = ResizeEdges(rawValue: 1 << 1)
    static let top    = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)
}

// MARK: - SnapMode

enum SnapMode {
    case none       // FN only — no snapping
    case windows    // FN + Shift — snap to other window edges
    case grid       // FN + Control — snap to grid lines
}

// MARK: - GridSnapper

struct GridSnapper {

    /// Maximum distance to a snap candidate before snapping is ignored.
    static let snapThreshold: CGFloat = 20
    /// Minimum allowed window dimension after resize.
    static let minWindowSize = CGSize(width: 100, height: 100)

    // MARK: - Drag zone detection

    /// Returns the drag zone for a click at `point` inside `windowFrame`.
    ///
    /// Clicks within `borderWidth` points of any edge trigger resize.
    /// The border is clamped to at most 40 % of the relevant dimension so the
    /// move zone never disappears on small windows.
    static func dragZone(at point: CGPoint, in windowFrame: CGRect, borderWidth: CGFloat) -> DragZone {
        let maxFraction: CGFloat = 0.4
        let hBorder = min(borderWidth, windowFrame.width  * maxFraction)
        let vBorder = min(borderWidth, windowFrame.height * maxFraction)

        let distLeft   = point.x - windowFrame.minX
        let distRight  = windowFrame.maxX - point.x
        let distTop    = point.y - windowFrame.minY
        let distBottom = windowFrame.maxY - point.y

        var edges = ResizeEdges()
        if distLeft   < hBorder { edges.insert(.left)   }
        if distRight  < hBorder { edges.insert(.right)  }
        if distTop    < vBorder { edges.insert(.top)    }
        if distBottom < vBorder { edges.insert(.bottom) }

        return edges.isEmpty ? .move : .resize(edges)
    }

    // MARK: - Candidate frame

    /// Computes an unsnapped candidate frame from the drag start state and current mouse delta.
    static func candidateFrame(startFrame: CGRect, delta: CGPoint, zone: DragZone) -> CGRect {
        switch zone {
        case .move:
            return startFrame.offsetBy(dx: delta.x, dy: delta.y)

        case .resize(let edges):
            var r = startFrame

            if edges.contains(.right) {
                r.size.width = max(startFrame.width + delta.x, minWindowSize.width)
            }
            if edges.contains(.left) {
                let newMinX = startFrame.minX + delta.x
                let newWidth = startFrame.maxX - newMinX
                if newWidth >= minWindowSize.width {
                    r.origin.x = newMinX
                    r.size.width = newWidth
                } else {
                    r.origin.x = startFrame.maxX - minWindowSize.width
                    r.size.width = minWindowSize.width
                }
            }
            if edges.contains(.bottom) {
                r.size.height = max(startFrame.height + delta.y, minWindowSize.height)
            }
            if edges.contains(.top) {
                let newMinY = startFrame.minY + delta.y
                let newHeight = startFrame.maxY - newMinY
                if newHeight >= minWindowSize.height {
                    r.origin.y = newMinY
                    r.size.height = newHeight
                } else {
                    r.origin.y = startFrame.maxY - minWindowSize.height
                    r.size.height = minWindowSize.height
                }
            }
            return r
        }
    }

    // MARK: - Snapping

    /// Snaps `candidate` according to `snapMode`:
    /// - `.none`    — returns the candidate unchanged
    /// - `.windows` — snaps to the edges of other on-screen windows (FN + Shift)
    /// - `.grid`    — snaps to grid lines; when moving, snaps to the nearest full grid cell
    static func snap(
        candidate: CGRect,
        otherWindows: [WindowInfo],
        zone: DragZone,
        gridStore: GridConfigStore,
        snapMode: SnapMode,
        cursorLocation: CGPoint
    ) -> CGRect {
        guard snapMode != .none else { return candidate }
        guard let screen = containingScreen(for: cursorLocation) else { return candidate }
        let screenCG = cgFrame(of: screen)

        // Grid + move: snap position AND resize to fit the nearest cell.
        if snapMode == .grid, case .move = zone {
            return snapToGridCell(
                screenCG: screenCG,
                columns: gridStore.columns(for: screen),
                rows: gridStore.rows(for: screen),
                cursorLocation: cursorLocation
            )
        }

        let xCandidates: [CGFloat]
        let yCandidates: [CGFloat]

        let threshold: CGFloat
        switch snapMode {
        case .grid:
            xCandidates = gridXLines(screenCG: screenCG, columns: gridStore.columns(for: screen))
            yCandidates = gridYLines(screenCG: screenCG, rows: gridStore.rows(for: screen))
            threshold = .infinity   // always snap to the nearest grid line
        case .windows:
            var xs: [CGFloat] = []
            var ys: [CGFloat] = []
            for w in otherWindows {
                xs.append(w.frame.minX); xs.append(w.frame.maxX)
                ys.append(w.frame.minY); ys.append(w.frame.maxY)
            }
            for s in NSScreen.screens {
                let sc = cgFrame(of: s)
                xs.append(sc.minX); xs.append(sc.maxX)
                ys.append(sc.minY); ys.append(sc.maxY)
            }
            xCandidates = xs
            yCandidates = ys
            threshold = .infinity   // always snap to the nearest window/screen edge
        case .none:
            return candidate
        }

        return applySnap(to: candidate, xCandidates: xCandidates, yCandidates: yCandidates, zone: zone, threshold: threshold)
    }

    // MARK: - Private helpers

    /// Converts an NSScreen frame (AppKit coords: bottom-left origin, Y up)
    /// into a CoreGraphics rect (top-left origin, Y down).
    ///
    /// Uses `NSScreen.screens.first` (the stable primary/reference display) for the Y-flip height.
    /// `NSScreen.main` must NOT be used here — it returns the screen with the key window and
    /// changes whenever focus switches, corrupting the coordinate conversion mid-drag.
    static func cgFrame(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    /// Returns the NSScreen that contains `point` (CG coords).
    ///
    /// Uses the cursor position rather than the candidate window frame so that the target screen
    /// is always the one the user is pointing at — a tall candidate frame near a screen edge
    /// could otherwise overlap an adjacent screen more than the current one, causing wrong snapping.
    private static func containingScreen(for point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { cgFrame(of: $0).contains(point) })
    }

    private static func gridXLines(screenCG: CGRect, columns: Int) -> [CGFloat] {
        let cellW = screenCG.width / CGFloat(columns)
        return (0...columns).map { screenCG.minX + CGFloat($0) * cellW }
    }

    private static func gridYLines(screenCG: CGRect, rows: Int) -> [CGFloat] {
        let cellH = screenCG.height / CGFloat(rows)
        return (0...rows).map { screenCG.minY + CGFloat($0) * cellH }
    }

    /// Returns the nearest value in `candidates` to `value` together with the distance.
    private static func nearest(_ value: CGFloat, in candidates: [CGFloat]) -> (value: CGFloat, dist: CGFloat)? {
        guard !candidates.isEmpty else { return nil }
        var best     = candidates[0]
        var bestDist = abs(candidates[0] - value)
        for c in candidates.dropFirst() {
            let d = abs(c - value)
            if d < bestDist { bestDist = d; best = c }
        }
        return (best, bestDist)
    }

    /// Returns the snapped grid rectangle for the cursor position.
    ///
    /// Height is determined by where the cursor sits within its row:
    /// - Cursor in top half of row → 1 cell height.
    /// - Cursor in bottom half of row and a row below exists → 2 cells height.
    /// - Cursor within the bottom 25 % of a cell height from the screen's bottom edge
    ///   (only when the grid has more than 2 rows) → full screen height, y = screen top.
    private static func snapToGridCell(
        screenCG: CGRect,
        columns: Int,
        rows: Int,
        cursorLocation: CGPoint
    ) -> CGRect {
        let cellW = screenCG.width  / CGFloat(columns)
        let cellH = screenCG.height / CGFloat(rows)

        let col = floor((cursorLocation.x - screenCG.minX) / cellW)
        let row = floor((cursorLocation.y - screenCG.minY) / cellH)

        let clampedCol = max(0, min(CGFloat(columns - 1), col))
        let clampedRow = max(0, min(CGFloat(rows    - 1), row))

        let windowX = screenCG.minX + clampedCol * cellW
        let rowTop  = screenCG.minY + clampedRow * cellH

        // Near bottom edge of screen (3+ row grids only) → full screen height.
        if rows > 2 && (screenCG.maxY - cursorLocation.y) < cellH * 0.25 {
            return CGRect(x: windowX, y: screenCG.minY, width: cellW, height: screenCG.height)
        }

        // Cursor in bottom half of row and a row exists below → span 2 rows.
        let posInRow = cursorLocation.y - rowTop
        let spanTwo  = posInRow >= cellH * 0.5 && clampedRow < CGFloat(rows - 1)
        let height   = spanTwo ? cellH * 2 : cellH

        return CGRect(x: windowX, y: rowTop, width: cellW, height: height)
    }

    private static func applySnap(
        to frame: CGRect,
        xCandidates: [CGFloat],
        yCandidates: [CGFloat],
        zone: DragZone,
        threshold: CGFloat
    ) -> CGRect {
        var r = frame

        // --- X axis ---
        switch zone {
        case .move:
            // Snap whichever of left/right edge is nearer to a candidate.
            let snapLeft  = nearest(frame.minX, in: xCandidates)
            let snapRight = nearest(frame.maxX, in: xCandidates)
            let leftDist  = snapLeft?.dist  ?? .infinity
            let rightDist = snapRight?.dist ?? .infinity
            if leftDist <= rightDist, let s = snapLeft, s.dist < threshold {
                r.origin.x = s.value
            } else if let s = snapRight, s.dist < threshold {
                r.origin.x = s.value - frame.width
            }
        case .resize(let edges):
            if edges.contains(.left),
               let snap = nearest(frame.minX, in: xCandidates),
               snap.dist < threshold {
                let newWidth = frame.maxX - snap.value
                if newWidth >= minWindowSize.width {
                    r.origin.x  = snap.value
                    r.size.width = newWidth
                }
            }
            if edges.contains(.right),
               let snap = nearest(frame.maxX, in: xCandidates),
               snap.dist < threshold {
                let newWidth = snap.value - frame.minX
                if newWidth >= minWindowSize.width {
                    r.size.width = newWidth
                }
            }
        }

        // --- Y axis ---
        switch zone {
        case .move:
            // Snap whichever of top/bottom edge is nearer to a candidate.
            let snapTop    = nearest(frame.minY, in: yCandidates)
            let snapBottom = nearest(frame.maxY, in: yCandidates)
            let topDist    = snapTop?.dist    ?? .infinity
            let bottomDist = snapBottom?.dist ?? .infinity
            if topDist <= bottomDist, let s = snapTop, s.dist < threshold {
                r.origin.y = s.value
            } else if let s = snapBottom, s.dist < threshold {
                r.origin.y = s.value - frame.height
            }
        case .resize(let edges):
            if edges.contains(.top),
               let snap = nearest(frame.minY, in: yCandidates),
               snap.dist < threshold {
                let newHeight = frame.maxY - snap.value
                if newHeight >= minWindowSize.height {
                    r.origin.y   = snap.value
                    r.size.height = newHeight
                }
            }
            if edges.contains(.bottom),
               let snap = nearest(frame.maxY, in: yCandidates),
               snap.dist < threshold {
                let newHeight = snap.value - frame.minY
                if newHeight >= minWindowSize.height {
                    r.size.height = newHeight
                }
            }
        }
        // NSLog("right edge: %@", String(describing: r.maxX))

        return r
    }
}
