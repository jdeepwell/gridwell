import SwiftUI
import AppKit
import Combine
import Sparkle

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}

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
    @State private var screens: [NSScreen] = []

    var body: some View {
        VStack(spacing: 16) {
            ForEach(screens, id: \.displayID) { screen in
                ScreenGridRow(screen: screen)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            screens = NSScreen.screens
        }
    }
}

// MARK: - Per-screen row

private struct ScreenGridRow: View {
    let screen: NSScreen
    @EnvironmentObject private var store: GridConfigStore

    private var columns: Int { store.columns(for: screen) }
    private var rows: Int    { store.rows(for: screen) }

    var body: some View {
        PreferenceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(screen.localizedName)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(Int(screen.frame.width * screen.backingScaleFactor)) × \(Int(screen.frame.height * screen.backingScaleFactor))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .monospacedDigit()
                }

                GridPreviewShape(columns: columns, rows: rows)
                    .aspectRatio(screen.frame.width / screen.frame.height, contentMode: .fit)
                    .frame(maxWidth: 250, maxHeight: 108)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18))
                    }

                GridCountSlider(
                    label: "Columns",
                    value: Binding(get: { columns }, set: { store.setColumns($0, for: screen) }),
                    range: 1...12
                )

                GridCountSlider(
                    label: "Rows",
                    value: Binding(get: { rows }, set: { store.setRows($0, for: screen) }),
                    range: 1...8
                )
            }
        }
    }
}

// MARK: - Grid count slider

private struct GridCountSlider: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    private var doubleValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { newValue in
                value = min(max(Int(newValue.rounded()), range.lowerBound), range.upperBound)
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.callout.weight(.semibold))
                .frame(width: 72, alignment: .leading)

            ZStack {
                SliderTickMarks(count: range.count)
                    .padding(.horizontal, 2)

                Slider(value: doubleValue, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .controlSize(.small)
            }
            .frame(height: 18)

            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 28, alignment: .trailing)
                .accessibilityLabel("\(label): \(value)")
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

            let rect = CGRect(origin: .zero, size: size)
            let background = Color(red: 0.10, green: 0.12, blue: 0.14)
            let alternate = Color(red: 0.13, green: 0.16, blue: 0.19)
            let majorLine = Color(red: 0.24, green: 0.58, blue: 0.98)
            let minorLine = Color(red: 0.80, green: 0.88, blue: 0.92)

            ctx.fill(
                Path(rect),
                with: .color(background)
            )

            for column in 0..<columns {
                for row in 0..<rows where (column + row).isMultiple(of: 2) {
                    let cellRect = CGRect(
                        x: CGFloat(column) * colWidth,
                        y: CGFloat(row) * rowHeight,
                        width: colWidth,
                        height: rowHeight
                    )
                    ctx.fill(Path(cellRect), with: .color(alternate))
                }
            }

            for i in 1..<columns {
                let x = colWidth * CGFloat(i)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(majorLine.opacity(0.82)), lineWidth: 1.2)
            }

            for i in 1..<rows {
                let y = rowHeight * CGFloat(i)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(minorLine.opacity(0.42)), lineWidth: 1)
            }

            ctx.stroke(
                Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                with: .color(Color.white.opacity(0.28)),
                lineWidth: 1
            )
        }
    }
}

// MARK: - Behaviour tab

private struct BehaviourTab: View {
    @EnvironmentObject private var store: GridConfigStore

    var body: some View {
        VStack(spacing: 16) {
            PreferenceToggleCard(
                title: "Raise window to front when dragging",
                detail: "Bring window forward automatically on drag start",
                isOn: Binding(
                    get: { store.raiseWindowOnDrag },
                    set: { store.setRaiseWindowOnDrag($0) }
                )
            )

            PreferenceCard {
                VStack(alignment: .leading, spacing: 16) {
                    PreferenceSectionTitle("Minimum Window Size")

                    HStack(alignment: .top, spacing: 30) {
                        PreferenceSliderControl(
                            label: "Width",
                            value: Binding(
                                get: { store.minWindowWidth },
                                set: { store.setMinWindowWidth($0) }
                            ),
                            range: 0...500,
                            step: 10
                        )

                        PreferenceSliderControl(
                            label: "Height",
                            value: Binding(
                                get: { store.minWindowHeight },
                                set: { store.setMinWindowHeight($0) }
                            ),
                            range: 0...500,
                            step: 10
                        )
                    }

                    Text("Set to 0 to disable. Windows smaller than these values are ignored.")
                        .preferenceHelpText()
                }
            }

            PreferenceCard {
                VStack(alignment: .leading, spacing: 16) {
                    PreferenceSectionTitle("Resize Border")

                    HStack(alignment: .top, spacing: 30) {
                        PreferencePercentSliderControl(
                            label: "Percentage",
                            value: Binding(
                                get: { store.resizeBorderPercent },
                                set: { store.setResizeBorderPercent($0) }
                            ),
                            range: 1...50,
                            step: 1
                        )

                        PreferenceSliderControl(
                            label: "Minimum",
                            value: Binding(
                                get: { store.resizeBorderMinPixels },
                                set: { store.setResizeBorderMinPixels($0) }
                            ),
                            range: 0...300,
                            step: 5,
                            tickCount: 61
                        )
                    }

                    Text("Drag zone near a window edge = max(dimension × %, minimum px). Clamped to 40% of window dimension.")
                        .preferenceHelpText()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Behaviour controls

private struct PreferenceCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

private struct PreferenceToggleCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        PreferenceCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(detail)
                        .preferenceHelpText()
                }

                Spacer()

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

private struct PreferenceSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct PreferenceSliderControl: View {
    let label: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var tickCount: Int = 35

    private var doubleValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { newValue in
                let stepped = (newValue / Double(step)).rounded() * Double(step)
                value = min(max(Int(stepped), range.lowerBound), range.upperBound)
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                if let label {
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    SliderTickMarks(count: tickCount)
                        .padding(.horizontal, 1)
                    Slider(value: doubleValue, in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                        .controlSize(.small)
                }
                .frame(height: 18)
            }

            VStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("pt")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)
            .accessibilityLabel(value == 0 ? "off" : "\(value) points")
        }
    }
}

private struct PreferencePercentSliderControl: View {
    let label: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var tickCount: Int = 25

    init(label: String?, value: Binding<Double>, range: ClosedRange<Double>, step: Double, tickCount: Int = 25) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.tickCount = tickCount
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                if let label {
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    SliderTickMarks(count: tickCount)
                        .padding(.horizontal, 1)
                    Slider(value: $value, in: range, step: step)
                        .controlSize(.small)
                }
                .frame(height: 18)
            }

            VStack(spacing: 0) {
                Text("\(Int(value))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)
            .accessibilityLabel("\(Int(value)) percent")
        }
    }
}

private struct SliderTickMarks: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(Color.secondary.opacity(index % 5 == 0 ? 0.5 : 0.28))
                    .frame(width: 1, height: index % 5 == 0 ? 9 : 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }
}

private extension Text {
    func preferenceHelpText() -> some View {
        self
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Keys tab

private struct KeysTab: View {
    @EnvironmentObject private var store: GridConfigStore

    var body: some View {
        VStack(spacing: 16) {
            PreferenceCard {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        PreferenceSectionTitle("Drag Trigger")

                        Text("Start moving or resizing windows")
                            .font(.callout.weight(.semibold))

                        Text("Click the badge, press a shortcut, then release all keys.")
                            .preferenceHelpText()
                    }
                    .layoutPriority(1)

                    Spacer()

                    ShortcutRecorderRow(
                        shortcut: Binding(get: { store.triggerShortcut },
                                          set: { store.setTriggerShortcut($0) })
                    )
                }
            }

            PreferenceCard {
                VStack(alignment: .leading, spacing: 14) {
                    PreferenceSectionTitle("Snap Modifiers")

                    Text("Hold one while dragging to choose the snap target.")
                        .preferenceHelpText()

                    KeyPickerRow(
                        title: "All windows",
                        detail: "Other apps and screen edges",
                        selection: Binding(get: { store.windowSnapKey },
                                           set: { store.setWindowSnapKey($0) })
                    )

                    Divider()

                    KeyPickerRow(
                        title: "Same app",
                        detail: "Only windows from the current app",
                        selection: Binding(get: { store.appWindowSnapKey },
                                           set: { store.setAppWindowSnapKey($0) })
                    )

                    Divider()

                    KeyPickerRow(
                        title: "Grid",
                        detail: "Personal grid positions",
                        selection: Binding(get: { store.gridSnapKey },
                                           set: { store.setGridSnapKey($0) })
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
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
    @Binding var shortcut: TriggerShortcut
    @StateObject private var recorder = RecorderState()

    var body: some View {
        HStack(spacing: 8) {
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
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .frame(minWidth: 96, minHeight: 24, alignment: .center)
                    .animation(nil, value: display)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(recorder.isRecording ? "Recording shortcut" : "Record shortcut")

            if recorder.isRecording {
                Button("Cancel") { recorder.cancel() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Key picker row

private struct KeyPickerRow: View {
    let title: String
    let detail: String
    @Binding var selection: ModifierKey

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .preferenceHelpText()
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(ModifierKey.allCases, id: \.self) { key in
                    Text(key.symbol + "  " + key.displayName).tag(key)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.regular)
            .frame(width: 138)
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
        .frame(minWidth: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    PreferencesView()
        .environmentObject(GridConfigStore.shared)
}
