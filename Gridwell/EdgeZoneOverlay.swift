import AppKit

/// A click-through strip that highlights a screen edge zone: the bottom minimize zone while a
/// dragged window is in it, or any zone while the zone settings are being adjusted.
///
/// Borderless, non-activating panel above normal windows and the Dock, on all Spaces.
/// Its layer is above 0, so WindowInfoProvider never treats it as a draggable window.
/// Main thread only.
final class EdgeZoneOverlay {

    enum Edge { case left, right, bottom }

    private let edge: Edge
    private var panel: NSPanel?
    private var isShown = false

    init(edge: Edge = .bottom) {
        self.edge = edge
    }

    /// Shows the strip over `cgRect` (CoreGraphics coords), fading in if it was hidden.
    func show(at cgRect: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let frame = cgToAppKit(cgRect)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        guard !isShown else { return }
        isShown = true

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    /// Fades the strip out.
    func hide() {
        guard isShown, let panel else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A show() during the fade-out takes precedence.
            if self?.isShown == false { panel.orderOut(nil) }
        })
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: true)
        panel.level = .statusBar                // above normal windows and the Dock
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = StripView(edge: edge)
        return panel
    }

    /// Converts a CoreGraphics rect (origin top-left of primary screen, Y down) to AppKit coords.
    private func cgToAppKit(_ cgRect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: cgRect.minX, y: primaryHeight - cgRect.maxY,
                      width: cgRect.width, height: cgRect.height)
    }
}

// MARK: - Strip view

/// Translucent accent-coloured band, rounded on the corners facing the screen centre, with a
/// symbol for the zone's action: "minimize to Dock" at the bottom, "shrink" at the sides.
private final class StripView: NSView {

    private let edge: EdgeZoneOverlay.Edge
    private let symbolView = NSImageView()

    init(edge: EdgeZoneOverlay.Edge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true

        let symbol = edge == .bottom ? "arrow.down.to.line" : "arrow.down.right.and.arrow.up.left"
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        symbolView.image = NSImage(systemSymbolName: symbol,
                                   accessibilityDescription: edge == .bottom ? "Minimize" : "Shrink")?
            .withSymbolConfiguration(config)
        symbolView.contentTintColor = .white
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateLayer() {
        guard let layer else { return }
        let accent = NSColor.controlAccentColor
        layer.backgroundColor = accent.withAlphaComponent(0.35).cgColor
        layer.borderColor = accent.withAlphaComponent(0.9).cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 10
        // Round the corners facing the screen centre (layer coords: Y up).
        switch edge {
        case .bottom: layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .left:   layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .right:  layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
    }

    override var wantsUpdateLayer: Bool { true }
}

// MARK: - Zone preview

/// Shows the edge zones of all screens while the zone settings are adjusted in the preferences.
/// Reads the current values from GridConfigStore on every `refresh()`. Main thread only.
final class EdgeZonePreview {

    static let shared = EdgeZonePreview()

    private var overlays: [EdgeZoneOverlay] = []
    private var isActive = false
    private var pendingHide: DispatchWorkItem?

    /// Linger after the slider is released so a quick click still shows the zones.
    private let hideDelay: TimeInterval = 1.0

    /// Call with true when a zone slider starts being dragged, false when it is released.
    func setEditing(_ editing: Bool) {
        pendingHide?.cancel()
        pendingHide = nil
        if editing {
            isActive = true
            refresh()
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.isActive = false
                self?.overlays.forEach { $0.hide() }
            }
            pendingHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: work)
        }
    }

    /// Re-lays out the zones from the current settings. No-op while the preview is not active.
    func refresh() {
        guard isActive else { return }
        let store = GridConfigStore.shared
        var rects: [(EdgeZoneOverlay.Edge, CGRect)] = []
        for screen in NSScreen.screens {
            let frame = GridSnapper.cgFrame(of: screen)
            let width = GridSnapper.edgeZoneWidth(in: frame, percent: store.edgeZonePercent)
            rects.append((.left,  CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height)))
            rects.append((.right, CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)))
            rects.append((.bottom, GridSnapper.minimizeZoneRect(in: frame, zoneWidth: width,
                                                                bottomHeight: CGFloat(store.bottomZoneHeight))))
        }

        // One overlay per rect, reused across refreshes; the edge of a slot never changes
        // as long as the screen count does, so rebuild only when the count differs.
        if overlays.count != rects.count {
            overlays.forEach { $0.hide() }
            overlays = rects.map { EdgeZoneOverlay(edge: $0.0) }
        }
        for (overlay, rect) in zip(overlays, rects) {
            overlay.show(at: rect.1)
        }
    }
}
