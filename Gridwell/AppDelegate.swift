import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var modifierKeyMonitor: ModifierKeyMonitor?
    private var mouseInteractionHandler: MouseInteractionHandler?
    private let windowInfoProvider = WindowInfoProvider()
    private var permissionsWindowController: PermissionsWindowController?

    override init() {
        super.init()
        NSLog("[AppDelegate] init — delegate is alive")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching")
        requestAccessibilityPermissions()
        windowInfoProvider.refresh()

        // When the last visible key window closes, revert to accessory policy
        // so no Dock icon remains while settings is not showing.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private func requestAccessibilityPermissions() {
        // Check without prompting first
        let trusted = AXIsProcessTrustedWithOptions(nil)
        NSLog("[AppDelegate] Accessibility trusted: %@", trusted ? "YES" : "NO")

        if trusted {
            startMonitoring()
        } else {
            showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Gridwell needs Accessibility access to manage windows.\n\nClick Open Settings to grant access, then return to Gridwell."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)

            let wc = PermissionsWindowController()
            self.permissionsWindowController = wc
            Task { @MainActor in
                await activateAppForUI()
                wc.showWindow(nil)
            }

            waitForAccessibilityPermission()
        } else {
            NSApp.terminate(nil)
        }
    }

    private func waitForAccessibilityPermission() {
        NSLog("[AppDelegate] Waiting for accessibility permission...")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                NSLog("[AppDelegate] Accessibility permission granted")
                timer.invalidate()
                self?.permissionsWindowController?.transitionToWelcome {
                    self?.permissionsWindowController = nil
                }
                self?.startMonitoring()
            }
        }
    }

    private func startMonitoring() {
        modifierKeyMonitor = ModifierKeyMonitor()
        modifierKeyMonitor?.start()

        mouseInteractionHandler = MouseInteractionHandler(
            windowInfoProvider: windowInfoProvider,
            modifierKeyMonitor: modifierKeyMonitor!
        )
        mouseInteractionHandler?.start()
    }
}
