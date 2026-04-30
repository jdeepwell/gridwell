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

    // Current UserDefaults keys
    private let userDefaultsKey        = "gridConfig"
    private let raiseOnDragKey         = "raiseWindowOnDrag"
    private let minWindowWidthKey      = "minWindowWidth"
    private let minWindowHeightKey     = "minWindowHeight"
    private let resizeBorderWidthKey   = "resizeBorderWidth"
    private let triggerShortcutKey     = "triggerShortcut"
    private let windowSnapKeyKey       = "windowSnapKey"
    private let appWindowSnapKeyKey    = "appWindowSnapKey"
    private let gridSnapKeyKey         = "gridSnapKey"
    private let settingsVersionKey     = "settingsVersion"

    // Legacy keys — used only inside migration functions
    private let lk_v0_triggerKey          = "com.gridwell.triggerKey"
    private let lk_v1_settingsVersion     = "com.gridwell.settingsVersion"
    private let lk_v1_gridConfig          = "com.gridwell.gridConfig"
    private let lk_v1_raiseWindowOnDrag   = "com.gridwell.raiseWindowOnDrag"
    private let lk_v1_triggerShortcut     = "com.gridwell.triggerShortcut"
    private let lk_v1_windowSnapKey       = "com.gridwell.windowSnapKey"
    private let lk_v1_gridSnapKey         = "com.gridwell.gridSnapKey"

    private static let currentSettingsVersion = 2

    /// Maps screen key → grid config. Missing keys fall back to defaults.
    @Published private var config: [String: ScreenGridConfig] = [:]

    /// When true, the interacted window is raised to the front at drag start.
    @Published private(set) var raiseWindowOnDrag: Bool = true

    /// Minimum window width in points. Windows narrower than this are ignored.
    @Published private(set) var minWindowWidth: Int = 100

    /// Minimum window height in points. Windows shorter than this are ignored.
    @Published private(set) var minWindowHeight: Int = 100

    /// Width of the resize border in points. Clicks within this distance of any edge trigger resize.
    /// Clamped to 40 % of the relevant window dimension at runtime.
    @Published private(set) var resizeBorderWidth: Int = 150

    /// Key combination that must be held to initiate a drag.
    @Published private(set) var triggerShortcut: TriggerShortcut = .defaultFN

    /// Modifier key held during drag to snap to all other window edges.
    @Published private(set) var windowSnapKey: ModifierKey = .shift

    /// Modifier key held during drag to snap to windows of the same application.
    @Published private(set) var appWindowSnapKey: ModifierKey = .option

    /// Modifier key held during drag to snap to the grid.
    @Published private(set) var gridSnapKey: ModifierKey = .control

    private init() {
        runMigrations()
        if let saved = UserDefaults.standard.object(forKey: raiseOnDragKey) as? Bool {
            raiseWindowOnDrag = saved
        }
        if let w = UserDefaults.standard.object(forKey: minWindowWidthKey) as? Int {
            minWindowWidth = w
        }
        if let h = UserDefaults.standard.object(forKey: minWindowHeightKey) as? Int {
            minWindowHeight = h
        }
        if let b = UserDefaults.standard.object(forKey: resizeBorderWidthKey) as? Int {
            resizeBorderWidth = b
        }
        triggerShortcut  = loadTriggerShortcut()
        windowSnapKey    = loadModifierKey(forKey: windowSnapKeyKey,    default: .shift)
        appWindowSnapKey = loadModifierKey(forKey: appWindowSnapKeyKey, default: .option)
        gridSnapKey      = loadModifierKey(forKey: gridSnapKeyKey,      default: .control)
        load()
    }

    // MARK: Migrations

    private func runMigrations() {
        // The version key itself was renamed in v2; check new key first, then old.
        let stored: Int
        if UserDefaults.standard.object(forKey: settingsVersionKey) != nil {
            stored = UserDefaults.standard.integer(forKey: settingsVersionKey)
        } else if UserDefaults.standard.object(forKey: lk_v1_settingsVersion) != nil {
            stored = UserDefaults.standard.integer(forKey: lk_v1_settingsVersion)
        } else {
            stored = 0
        }
        guard stored < Self.currentSettingsVersion else { return }

        if stored < 1 { migrate0to1() }
        if stored < 2 { migrate1to2() }

        UserDefaults.standard.set(Self.currentSettingsVersion, forKey: settingsVersionKey)
    }

    /// v0 → v1: migrate legacy single-ModifierKey trigger to TriggerShortcut.
    /// Writes to the v1 key names (com.gridwell.*); migrate1to2 will rename them.
    private func migrate0to1() {
        guard let raw = UserDefaults.standard.string(forKey: lk_v0_triggerKey),
              let legacy = ModifierKey(rawValue: raw) else { return }
        let migrated = TriggerShortcut(
            modifierFlagsRaw: legacy.nsModifierFlag.rawValue,
            keyCode: nil,
            keyDisplayString: nil
        )
        if let data = try? JSONEncoder().encode(migrated) {
            UserDefaults.standard.set(data, forKey: lk_v1_triggerShortcut)
        }
        NSLog("[GridConfigStore] Migrated legacy triggerKey '%@' to TriggerShortcut", raw)
        NSLog("[GridConfigStore] Migrated settings from 0 to 1")
    }

    /// v1 → v2: rename all com.gridwell.* keys to plain names.
    private func migrate1to2() {
        let ud = UserDefaults.standard
        let moves: [(from: String, to: String)] = [
            (lk_v1_gridConfig,        userDefaultsKey),
            (lk_v1_raiseWindowOnDrag, raiseOnDragKey),
            (lk_v1_triggerShortcut,   triggerShortcutKey),
            (lk_v1_windowSnapKey,     windowSnapKeyKey),
            (lk_v1_gridSnapKey,       gridSnapKeyKey),
        ]
        for (old, new) in moves {
            if let value = ud.object(forKey: old) {
                ud.set(value, forKey: new)
                ud.removeObject(forKey: old)
            }
        }
        ud.removeObject(forKey: lk_v0_triggerKey)
        ud.removeObject(forKey: lk_v1_settingsVersion)
        NSLog("[GridConfigStore] Migrated settings from 1 to 2")
    }

    func setRaiseWindowOnDrag(_ value: Bool) {
        raiseWindowOnDrag = value
        UserDefaults.standard.set(value, forKey: raiseOnDragKey)
    }

    func setMinWindowWidth(_ value: Int) {
        minWindowWidth = value
        UserDefaults.standard.set(value, forKey: minWindowWidthKey)
    }

    func setMinWindowHeight(_ value: Int) {
        minWindowHeight = value
        UserDefaults.standard.set(value, forKey: minWindowHeightKey)
    }

    func setResizeBorderWidth(_ value: Int) {
        resizeBorderWidth = value
        UserDefaults.standard.set(value, forKey: resizeBorderWidthKey)
    }

    func setTriggerShortcut(_ shortcut: TriggerShortcut) {
        triggerShortcut = shortcut
        saveTriggerShortcut(shortcut)
    }

    func setWindowSnapKey(_ key: ModifierKey) {
        windowSnapKey = key
        UserDefaults.standard.set(key.rawValue, forKey: windowSnapKeyKey)
    }

    func setAppWindowSnapKey(_ key: ModifierKey) {
        appWindowSnapKey = key
        UserDefaults.standard.set(key.rawValue, forKey: appWindowSnapKeyKey)
    }

    func setGridSnapKey(_ key: ModifierKey) {
        gridSnapKey = key
        UserDefaults.standard.set(key.rawValue, forKey: gridSnapKeyKey)
    }

    private func loadTriggerShortcut() -> TriggerShortcut {
        if let data = UserDefaults.standard.data(forKey: triggerShortcutKey),
           let decoded = try? JSONDecoder().decode(TriggerShortcut.self, from: data) {
            return decoded
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
