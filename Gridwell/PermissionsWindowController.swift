import AppKit

final class PermissionsWindowController: NSWindowController {

    private var onDismiss: (() -> Void)?

    init() {
        // Image is 1400×553 px @2x → 700×276 pt logical size.
        // Override the size so NSImage treats it as @2x; scaleNone then renders
        // it at exactly the view bounds with full Retina sharpness.
        let imageSize = NSSize(width: 700, height: 276)
        let img = NSImage(named: "waiting-for-permissions")!
        img.size = imageSize

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

        let img = NSImage(named: "where-is-gridwell")!
        // Treat as @2x Retina (same convention as waiting-for-permissions):
        // 1200×284 px physical → 600×142 pt logical.
        img.size = NSSize(width: img.size.width / 2, height: img.size.height / 2)
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

    @objc private func dismissWelcome() {
        guard let cb = onDismiss else { return }
        onDismiss = nil
        close()
        cb()
    }
}
