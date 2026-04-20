import AppKit

final class PermissionsWindowController: NSWindowController {

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
}
