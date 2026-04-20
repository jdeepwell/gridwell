import SwiftUI
import Combine
import Sparkle

// MARK: - UI activation helper

/// Promotes the app to `.regular` activation policy and activates it so that any
/// window opened immediately after will receive focus. Call this before opening any
/// window from a menu bar action. The AppDelegate's `NSWindow.willCloseNotification`
/// observer reverts to `.accessory` automatically once all windows are dismissed.
@MainActor
func activateAppForUI() async {
    NSApp.setActivationPolicy(.regular)
    try? await Task.sleep(for: .milliseconds(100))
    NSApp.activate(ignoringOtherApps: true)
}

// MARK: - Settings opener

@MainActor
func openSettingsWindow() async {
    await activateAppForUI()
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    try? await Task.sleep(for: .milliseconds(200))
    if let window = NSApp.windows.first(where: {
        $0.identifier?.rawValue == "com.apple.SwiftUI.Settings" ||
        ($0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeKey)
    }) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

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

    // MARK: Update preferences

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
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

    // MARK: Check for updates (with activation)

    /// Activates the app so Sparkle's windows receive focus, then triggers the check.
    /// Reverting to `.accessory` policy is handled automatically by AppDelegate's
    /// `NSWindow.willCloseNotification` observer once all Sparkle windows are closed.
    func activateAndCheckForUpdates() {
        Task { @MainActor in
            await activateAppForUI()
            updaterController.updater.checkForUpdates()
        }
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

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let sparkle: SparkleManager

    init(sparkle: SparkleManager) {
        self.sparkle = sparkle
        self.viewModel = CheckForUpdatesViewModel(updater: sparkle.updaterController.updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            sparkle.activateAndCheckForUpdates()
        }
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
            Button("Settings…") {
                Task { await openSettingsWindow() }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            if sparkle.updatePending {
                Button("Update Available…") {
                    sparkle.activateAndCheckForUpdates()
                }
                Divider()
            }

            CheckForUpdatesView(sparkle: sparkle)

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
                .environmentObject(sparkle)
        }
    }
}
