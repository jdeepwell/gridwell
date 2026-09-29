import AppKit

final class PermissionsWindowController: NSWindowController {

    private var onDismiss: (() -> Void)?

    init() {
        // Image is a 1x screenshot (743×404 px → 743×404 pt).
        let img = Self.loadImageAtPixelSize("waiting-for-permissions")
        let imageSize = img.size

        let imageView = NSImageView(image: img)
        imageView.imageScaling = .scaleNone

        let quitButton = NSButton(title: "Quit", target: nil, action: #selector(NSApplication.terminate(_:)))
        quitButton.bezelStyle = .rounded
        quitButton.keyEquivalent = "q"

        let stack = NSStackView(views: [imageView, quitButton])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: imageSize.height),
        ])

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gridwell — Accessibility Permission"
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Swaps the window content to the "where is it?" onboarding screen,
    // then auto-dismisses after 8 seconds or when the user clicks "Got it".
    func transitionToWelcome(onClose: @escaping () -> Void) {
        onDismiss = onClose

        // Image is a 1x screenshot (718×388 px → 718×388 pt).
        let img = Self.loadImageAtPixelSize("where-is-gridwell")
        let imageSize = img.size

        let imageView = NSImageView(image: img)
        imageView.imageScaling = .scaleNone

        let gotItButton = NSButton(title: "Got it", target: self, action: #selector(dismissWelcome))
        gotItButton.bezelStyle = .rounded
        gotItButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [imageView, gotItButton])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: imageSize.height),
        ])

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window?.title = "Gridwell — You're All Set!"
        window?.contentView = contentView
        window?.layoutIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.dismissWelcome()
        }
    }

    // Loads a bundled image and sizes it 1 pt per pixel, independent of the
    // DPI metadata stored in the PNG, so scaleNone shows it at its native size.
    private static func loadImageAtPixelSize(_ name: String) -> NSImage {
        let img = NSImage(named: name)!
        if let rep = img.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            img.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return img
    }

    @objc private func dismissWelcome() {
        guard let cb = onDismiss else { return }
        onDismiss = nil
        close()
        cb()
    }
}
