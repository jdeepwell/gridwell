import SwiftUI

@main
struct GridwellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Preferences...")
                }
                .keyboardShortcut(";", modifiers: .command)
            }
        }
    }
}
