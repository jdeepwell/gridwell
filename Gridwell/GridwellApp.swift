import SwiftUI
import Combine
import Sparkle

// MARK: - Notifications

extension Notification.Name {
    /// Posted by the Settings menu button to request the settings window be opened.
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
}

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

// MARK: - HiddenWindowView

/// A 1×1 invisible window whose sole purpose is to hold a valid SwiftUI environment
/// so that `openSettings()` can be called.
///
/// Background: `MenuBarExtra` apps run with `.accessory` activation policy (no Dock
/// icon) and macOS will not raise windows for apps without a Dock icon.  The fix is to
/// temporarily promote to `.regular`, activate, call `openSettings()` (which requires a
/// SwiftUI render-tree context — hence this window), then force the window to front.
/// Scene declaration order matters: this Window scene must appear *before* the
/// Settings scene so SwiftUI resolves `@Environment(\.openSettings)` correctly.
struct HiddenWindowView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    await activateAppForUI()
                    openSettings()
                    // Safety net: force the settings window to front after SwiftUI opens it.
                    try? await Task.sleep(for: .milliseconds(200))
                    if let window = NSApp.windows.first(where: {
                        $0.identifier?.rawValue == "com.apple.SwiftUI.Settings" ||
                        ($0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeKey)
                    }) {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
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

    init() {
        // The hidden Window scene opens automatically on launch; close it immediately
        // so it never appears to the user.
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue == "HiddenWindow" }?
                .close()
        }
    }

    var body: some Scene {
        // ⚠️ Must be declared BEFORE Settings so that HiddenWindowView's
        // @Environment(\.openSettings) resolves to the Settings scene below.
        Window("Hidden", id: "HiddenWindow") {
            HiddenWindowView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)

        MenuBarExtra("Gridwell", systemImage: "rectangle.3.group") {
            Button("Settings…") {
                NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
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

        // Settings scene — must come AFTER the hidden Window scene.
        Settings {
            PreferencesView()
                .environmentObject(GridConfigStore.shared)
                .environmentObject(sparkle)
        }
    }
}
