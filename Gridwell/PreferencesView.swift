import SwiftUI
import AppKit
import Combine
import Sparkle

// MARK: - Root

struct PreferencesView: View {
    var body: some View {
        TabView {
            GridPreferencesTab()
                .tabItem { Label("Grid", systemImage: "rectangle.split.3x1") }

            BehaviourTab()
                .tabItem { Label("Behaviour", systemImage: "slider.horizontal.3") }

            KeysTab()
                .tabItem { Label("Keys", systemImage: "keyboard") }

            UpdatesTab()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520)
    }
}

// MARK: - Grid tab

private struct GridPreferencesTab: View {
    @EnvironmentObject private var store: GridConfigStore

    var body: some View {
        let screens = NSScreen.screens
        return VStack(spacing: 16) {
            ForEach(screens, id: \.self) { screen in
                ScreenGridRow(screen: screen)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
    }
}

// MARK: - Per-screen row

private struct ScreenGridRow: View {
    let screen: NSScreen
    @EnvironmentObject private var store: GridConfigStore

    private var columns: Int { store.columns(for: screen) }
    private var rows: Int    { store.rows(for: screen) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {

                // Header: display name + native resolution
                HStack(alignment: .firstTextBaseline) {
                    Text(screen.localizedName)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(screen.frame.width * screen.backingScaleFactor)) × \(Int(screen.frame.height * screen.backingScaleFactor))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                // Visual grid preview scaled to the screen's aspect ratio
                GridPreviewShape(columns: columns, rows: rows)
                    .aspectRatio(screen.frame.width / screen.frame.height, contentMode: .fit)
                    .frame(maxHeight: 90)
                    .cornerRadius(3)

                // Columns stepper
                CountStepper(
                    label: "Columns",
                    value: Binding(get: { columns }, set: { store.setColumns($0, for: screen) }),
                    range: 1...12
                )

                // Rows stepper
                CountStepper(
                    label: "Rows",
                    value: Binding(get: { rows }, set: { store.setRows($0, for: screen) }),
                    range: 1...8
                )
            }
            .padding(6)
        }
    }
}

// MARK: - Custom stepper

private struct CountStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    if value > range.lowerBound { value -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .center)

                Button {
                    if value < range.upperBound { value += 1 }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .disabled(value >= range.upperBound)
            }
        }
    }
}

// MARK: - Grid preview

private struct GridPreviewShape: View {
    let columns: Int
    let rows: Int

    var body: some View {
        Canvas { ctx, size in
            let colWidth  = size.width  / CGFloat(columns)
            let rowHeight = size.height / CGFloat(rows)

            // Background
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.accentColor.opacity(0.08))
            )

            // Column dividers
            for i in 1..<columns {
                let x = colWidth * CGFloat(i)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(.accentColor.opacity(0.45)), lineWidth: 1)
            }

            // Row dividers
            for i in 1..<rows {
                let y = rowHeight * CGFloat(i)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.accentColor.opacity(0.45)), lineWidth: 1)
            }

            // Border
            ctx.stroke(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.secondary.opacity(0.4)),
                lineWidth: 1
            )
        }
    }
}

// MARK: - Behaviour tab

private struct BehaviourTab: View {
    @EnvironmentObject private var store: GridConfigStore

    var body: some View {
        Form {
            Toggle(
                "Raise window to front when dragging",
                isOn: Binding(
                    get: { store.raiseWindowOnDrag },
                    set: { store.setRaiseWindowOnDrag($0) }
                )
            )
        }
        .padding()
        .frame(minWidth: 520, minHeight: 100)
    }
}

// MARK: - Keys tab

private struct KeysTab: View {
    @EnvironmentObject private var store: GridConfigStore

    var body: some View {
        VStack(spacing: 16) {
            GroupBox("Drag Trigger") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Click the shortcut badge, then press the key combination you want to use. Release all keys to confirm.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    ShortcutRecorderRow(
                        label: "Trigger shortcut",
                        shortcut: Binding(get: { store.triggerShortcut },
                                          set: { store.setTriggerShortcut($0) })
                    )
                }
                .padding(6)
            }

            GroupBox("Snap Modifiers") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hold an additional modifier while dragging to activate snapping.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    KeyPickerRow(
                        label: "Snap to windows",
                        selection: Binding(get: { store.windowSnapKey },
                                           set: { store.setWindowSnapKey($0) })
                    )

                    Divider()

                    KeyPickerRow(
                        label: "Snap to grid",
                        selection: Binding(get: { store.gridSnapKey },
                                           set: { store.setGridSnapKey($0) })
                    )
                }
                .padding(6)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 220)
    }
}

// MARK: - Shortcut recorder state

/// Manages recording lifecycle and live display. Class so closures can mutate state
/// without capturing the (value-type) view struct.
@MainActor
private final class RecorderState: ObservableObject {
    @Published var isRecording = false
    @Published var live = TriggerShortcut.defaultFN

    private var shortcutBinding: Binding<TriggerShortcut>?
    private var monitors: [Any] = []

    // Tracks what is currently held during recording.
    private var currentFlags     = NSEvent.ModifierFlags()
    private var currentKeyCode:   UInt16? = nil
    private var currentKeyDisplay: String? = nil
    // The last non-empty snapshot — committed when all keys are released.
    private var lastNonEmpty: TriggerShortcut? = nil
    private var hasInput = false

    func startRecording(updating binding: Binding<TriggerShortcut>) {
        shortcutBinding  = binding
        isRecording      = true
        currentFlags     = []
        currentKeyCode   = nil
        currentKeyDisplay = nil
        lastNonEmpty     = nil
        hasInput         = false
        live = TriggerShortcut(modifierFlagsRaw: 0, keyCode: nil, keyDisplayString: nil)

        let m1 = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.onFlagsChanged(event)
            return event
        }
        let m2 = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.onKeyDown(event)
            return nil  // consume all key events while recording
        }
        let m3 = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.onKeyUp(event)
            return nil
        }
        monitors = [m1, m2, m3].compactMap { $0 }
    }

    func cancel() { tearDown(commit: false) }

    // MARK: - Event handlers (called on main thread by NSEvent monitors)

    private func onFlagsChanged(_ event: NSEvent) {
        let newFlags = event.modifierFlags.intersection(TriggerShortcut.relevantModifiers)
        // A modifier was pressed if newFlags contains any bit not in the previous currentFlags.
        let isPress = !newFlags.subtracting(currentFlags).isEmpty
        currentFlags = newFlags
        if !currentFlags.isEmpty { hasInput = true }
        updateLive(allowSnapshot: isPress)
        checkAllReleased()
    }

    private func onKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { cancel(); return }     // Escape — cancel without saving
        currentKeyCode    = event.keyCode
        currentKeyDisplay = Self.displayString(for: event)
        hasInput = true
        updateLive(allowSnapshot: true)     // key press — snapshot is valid
    }

    private func onKeyUp(_ event: NSEvent) {
        guard event.keyCode == currentKeyCode else { return }
        currentKeyCode    = nil
        currentKeyDisplay = nil
        updateLive(allowSnapshot: false)    // release — don't overwrite the snapshot
        checkAllReleased()
    }

    // MARK: - Helpers

    private func updateLive(allowSnapshot: Bool) {
        let candidate = TriggerShortcut(
            modifierFlagsRaw: currentFlags.rawValue,
            keyCode: currentKeyCode,
            keyDisplayString: currentKeyDisplay
        )
        live = candidate
        // Only snapshot on press events — releasing keys must not corrupt the stored peak state.
        if allowSnapshot && !candidate.displayString.isEmpty { lastNonEmpty = candidate }
    }

    private func checkAllReleased() {
        guard hasInput, currentFlags.isEmpty, currentKeyCode == nil else { return }
        tearDown(commit: true)
    }

    private func tearDown(commit: Bool) {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        isRecording = false
        if commit, let result = lastNonEmpty {
            shortcutBinding?.wrappedValue = result
        }
        shortcutBinding = nil
    }

    private static func displayString(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
            76: "↩", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        if let s = specialKeys[event.keyCode] { return s }
        return event.charactersIgnoringModifiers?.uppercased() ?? "(\(event.keyCode))"
    }
}

// MARK: - Shortcut recorder row

private struct ShortcutRecorderRow: View {
    let label: String
    @Binding var shortcut: TriggerShortcut
    @StateObject private var recorder = RecorderState()

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button {
                if recorder.isRecording {
                    recorder.cancel()
                } else {
                    recorder.startRecording(updating: $shortcut)
                }
            } label: {
                let display = recorder.isRecording
                    ? (recorder.live.displayString.isEmpty ? "Recording…" : recorder.live.displayString)
                    : shortcut.displayString
                Text(display)
                    .foregroundStyle(recorder.isRecording ? .red : .primary)
                    .frame(minWidth: 80, alignment: .center)
                    .animation(nil, value: display)
            }
            .buttonStyle(.bordered)

            if recorder.isRecording {
                Button("Cancel") { recorder.cancel() }
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Key picker row

private struct KeyPickerRow: View {
    let label: String
    @Binding var selection: ModifierKey

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(ModifierKey.allCases, id: \.self) { key in
                    Text(key.symbol + "  " + key.displayName).tag(key)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

// MARK: - Updates tab

private struct UpdatesTab: View {
    @EnvironmentObject private var sparkle: SparkleManager

    var body: some View {
        Form {
            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { sparkle.automaticallyChecksForUpdates },
                    set: { sparkle.automaticallyChecksForUpdates = $0 }
                )
            )
            CheckForUpdatesView(sparkle: sparkle)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 100)
    }
}

#Preview {
    PreferencesView()
        .environmentObject(GridConfigStore.shared)
}
