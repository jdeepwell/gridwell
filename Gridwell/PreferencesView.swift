import SwiftUI
import AppKit
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
                    Text("Hold this key and left-click anywhere in a window to start dragging or resizing.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    KeyPickerRow(
                        label: "Trigger key",
                        selection: Binding(get: { store.triggerKey },
                                           set: { store.setTriggerKey($0) })
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
        }
        .padding()
        .frame(minWidth: 520, minHeight: 100)
    }
}

#Preview {
    PreferencesView()
        .environmentObject(GridConfigStore.shared)
}
