import SwiftUI
import Combine
import Sparkle

// MARK: - SparkleManager

/// Owns the Sparkle updater controller and implements gentle scheduled-update
/// reminders so that background update alerts don't silently appear behind other
/// windows without the user noticing.
final class SparkleManager: NSObject, ObservableObject, SPUStandardUserDriverDelegate {

    /// True while a background-detected update is waiting for the user's attention.
    @Published var updatePending = false

    private(set) var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        // self is fully initialised after super.init(), so it is safe to pass as delegate.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Let Sparkle show the alert immediately when it's already in focus
        // (e.g. the user just checked manually or the system was idle).
        // For quiet background checks we handle the reminder ourselves.
        return immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            DispatchQueue.main.async { self.updatePending = true }
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        DispatchQueue.main.async { self.updatePending = false }
    }

    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async { self.updatePending = false }
    }
}

// MARK: - CheckForUpdatesView

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

// MARK: - GridwellApp

@main
struct GridwellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sparkle = SparkleManager()

    var body: some Scene {
        MenuBarExtra("Gridwell", systemImage: "rectangle.3.group") {
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            if sparkle.updatePending {
                Button("Update Available…") {
                    sparkle.updaterController.updater.checkForUpdates()
                }
                Divider()
            }

            CheckForUpdatesView(updater: sparkle.updaterController.updater)

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
