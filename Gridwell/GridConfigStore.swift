import AppKit
import Combine

// MARK: - Per-screen grid config

struct ScreenGridConfig: Codable {
    var columns: Int
    var rows: Int
}

// MARK: - Screen key

/// Returns a stable string identifier for `screen`.
/// Uses only point-space dimensions (e.g. "2560x1440") unless another screen in
/// `screens` shares the same dimensions, in which case the origin is appended
/// (e.g. "2560x1440@0,0") to disambiguate.
func screenKey(for screen: NSScreen, among screens: [NSScreen] = NSScreen.screens) -> String {
    let w = Int(screen.frame.width)
    let h = Int(screen.frame.height)
    let sizeStr = "\(w)x\(h)"
    let duplicates = screens.filter { Int($0.frame.width) == w && Int($0.frame.height) == h }
    if duplicates.count > 1 {
        return "\(sizeStr)@\(Int(screen.frame.origin.x)),\(Int(screen.frame.origin.y))"
    }
    return sizeStr
}

// MARK: - Defaults

/// Default column count based on screen width (in points).
func defaultColumnCount(for screen: NSScreen) -> Int {
    switch screen.frame.width {
    case 2560...: return 6
    case 1920...: return 4
    case 1280...: return 3
    default:      return 2
    }
}

/// Default row count — full-height columns per spec.
func defaultRowCount(for screen: NSScreen) -> Int { 1 }

// MARK: - Store

class GridConfigStore: ObservableObject {
    static let shared = GridConfigStore()

    private let userDefaultsKey      = "com.gridwell.gridConfig"
    private let raiseOnDragKey       = "com.gridwell.raiseWindowOnDrag"
    private let triggerShortcutKey   = "com.gridwell.triggerShortcut"
    private let legacyTriggerKeyKey  = "com.gridwell.triggerKey"   // read-only; used for one-time migration
    private let windowSnapKeyKey     = "com.gridwell.windowSnapKey"
    private let gridSnapKeyKey       = "com.gridwell.gridSnapKey"

    /// Maps screen key → grid config. Missing keys fall back to defaults.
    @Published private var config: [String: ScreenGridConfig] = [:]

    /// When true, the interacted window is raised to the front at drag start.
    @Published private(set) var raiseWindowOnDrag: Bool = true

    /// Key combination that must be held to initiate a drag.
    @Published private(set) var triggerShortcut: TriggerShortcut = .defaultFN

    /// Modifier key held during drag to snap to other window edges.
    @Published private(set) var windowSnapKey: ModifierKey = .shift

    /// Modifier key held during drag to snap to the grid.
    @Published private(set) var gridSnapKey: ModifierKey = .control

    private init() {
        if let saved = UserDefaults.standard.object(forKey: raiseOnDragKey) as? Bool {
            raiseWindowOnDrag = saved
        }
        triggerShortcut = loadTriggerShortcut()
        windowSnapKey   = loadModifierKey(forKey: windowSnapKeyKey, default: .shift)
        gridSnapKey     = loadModifierKey(forKey: gridSnapKeyKey,   default: .control)
        load()
    }

    func setRaiseWindowOnDrag(_ value: Bool) {
        raiseWindowOnDrag = value
        UserDefaults.standard.set(value, forKey: raiseOnDragKey)
    }

    func setTriggerShortcut(_ shortcut: TriggerShortcut) {
        triggerShortcut = shortcut
        saveTriggerShortcut(shortcut)
    }

    func setWindowSnapKey(_ key: ModifierKey) {
        windowSnapKey = key
        UserDefaults.standard.set(key.rawValue, forKey: windowSnapKeyKey)
    }

    func setGridSnapKey(_ key: ModifierKey) {
        gridSnapKey = key
        UserDefaults.standard.set(key.rawValue, forKey: gridSnapKeyKey)
    }

    private func loadTriggerShortcut() -> TriggerShortcut {
        // Try current format first.
        if let data = UserDefaults.standard.data(forKey: triggerShortcutKey),
           let decoded = try? JSONDecoder().decode(TriggerShortcut.self, from: data) {
            return decoded
        }
        // One-time migration from the legacy single-ModifierKey format.
        if let raw = UserDefaults.standard.string(forKey: legacyTriggerKeyKey),
           let legacy = ModifierKey(rawValue: raw) {
            let migrated = TriggerShortcut(
                modifierFlagsRaw: legacy.nsModifierFlag.rawValue,
                keyCode: nil,
                keyDisplayString: nil
            )
            saveTriggerShortcut(migrated)
            NSLog("[GridConfigStore] Migrated legacy triggerKey '%@' to TriggerShortcut", raw)
            return migrated
        }
        return .defaultFN
    }

    private func saveTriggerShortcut(_ shortcut: TriggerShortcut) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: triggerShortcutKey)
        }
    }

    private func loadModifierKey(forKey key: String, default fallback: ModifierKey) -> ModifierKey {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let value = ModifierKey(rawValue: raw) else { return fallback }
        return value
    }

    // MARK: Accessors

    func columns(for screen: NSScreen) -> Int {
        config[screenKey(for: screen)]?.columns ?? defaultColumnCount(for: screen)
    }

    func rows(for screen: NSScreen) -> Int {
        config[screenKey(for: screen)]?.rows ?? defaultRowCount(for: screen)
    }

    func setColumns(_ count: Int, for screen: NSScreen) {
        let key = screenKey(for: screen)
        config[key] = ScreenGridConfig(
            columns: count,
            rows: config[key]?.rows ?? defaultRowCount(for: screen)
        )
        save()
    }

    func setRows(_ count: Int, for screen: NSScreen) {
        let key = screenKey(for: screen)
        config[key] = ScreenGridConfig(
            columns: config[key]?.columns ?? defaultColumnCount(for: screen),
            rows: count
        )
        save()
    }

    // MARK: Persistence

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let decoded = try? JSONDecoder().decode([String: ScreenGridConfig].self, from: data)
        else { return }
        config = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
