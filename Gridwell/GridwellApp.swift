import SwiftUI

@main
struct GridwellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Gridwell", systemImage: "rectangle.3.group") {
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("About Gridwell") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationIcon: NSApp.applicationIconImage as Any
                ])
            }

            Divider()

            Button("Quit Gridwell") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            PreferencesView()
                .environmentObject(GridConfigStore.shared)
        }
    }
}
