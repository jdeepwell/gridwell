import AppKit

/// A click-through strip that highlights the bottom minimize zone while a dragged window is in it.
///
/// Borderless, non-activating panel above normal windows and the Dock, on all Spaces.
/// Its layer is above 0, so WindowInfoProvider never treats it as a draggable window.
/// Main thread only.
final class EdgeZoneOverlay {

    private var panel: NSPanel?
    private var isShown = false

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
        panel.contentView = StripView()
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

/// Translucent accent-coloured band with rounded top corners and a "minimize to Dock" symbol.
private final class StripView: NSView {

    private let symbolView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        symbolView.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "Minimize")?
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
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]   // top corners (AppKit: Y up)
    }

    override var wantsUpdateLayer: Bool { true }
}
