import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var modifierKeyMonitor: ModifierKeyMonitor?
    private var mouseInteractionHandler: MouseInteractionHandler?
    private let windowInfoProvider = WindowInfoProvider()

    override init() {
        super.init()
        NSLog("[AppDelegate] init — delegate is alive")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching")
        requestAccessibilityPermissions()
        windowInfoProvider.refresh()
    }

    // Reopen preferences when the user clicks the Dock icon with no windows open
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow()
        }
        return true
    }

    func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
        alert.informativeText = "Gridwell needs Accessibility access to manage windows.\n\nClick Open Settings to add Gridwell, then relaunch the app."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
        NSApp.terminate(nil)
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
