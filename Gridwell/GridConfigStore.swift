import AppKit
import Combine

// MARK: - Excluded app

/// An app excluded from the mouse button trigger. Bundle ID is the stable key;
/// name is stored alongside so the list renders correctly even when the app isn't running.
struct ExcludedApp: Codable, Equatable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

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
    private let userDefaultsKey            = "gridConfig"
    private let raiseOnDragKey             = "raiseWindowOnDrag"
    private let minWindowWidthKey          = "minWindowWidth"
    private let minWindowHeightKey         = "minWindowHeight"
    private let resizeBorderPercentKey     = "resizeBorderPercent"
    private let resizeBorderMinPixelsKey   = "resizeBorderMinPixels"
    private let edgeZoneWidthKey           = "edgeZoneWidth"
    private let edgeShrinkMinWidthKey      = "edgeShrinkMinWidth"
    private let bottomZoneHeightKey        = "bottomZoneHeight"
    private let triggerShortcutKey              = "triggerShortcut"
    private let mouseButtonTriggerKey           = "mouseButtonTrigger"
    private let mouseButtonExcludedAppsKey      = "mouseButtonExcludedApps"
    private let settingsVersionKey              = "settingsVersion"

    // Legacy keys — used only inside migration functions
    private let lk_v0_triggerKey          = "com.gridwell.triggerKey"
    private let lk_v1_settingsVersion     = "com.gridwell.settingsVersion"
    private let lk_v1_gridConfig          = "com.gridwell.gridConfig"
    private let lk_v1_raiseWindowOnDrag   = "com.gridwell.raiseWindowOnDrag"
    private let lk_v1_triggerShortcut     = "com.gridwell.triggerShortcut"
    private let lk_v1_windowSnapKey       = "com.gridwell.windowSnapKey"
    private let lk_v1_gridSnapKey         = "com.gridwell.gridSnapKey"
    private let lk_v2_resizeBorderWidth   = "resizeBorderWidth"
    private let lk_v3_windowSnapKey       = "windowSnapKey"
    private let lk_v3_appWindowSnapKey    = "appWindowSnapKey"
    private let lk_v3_gridSnapKey         = "gridSnapKey"

    private static let currentSettingsVersion = 4

    /// Maps screen key → grid config. Missing keys fall back to defaults.
    @Published private var config: [String: ScreenGridConfig] = [:]

    /// When true, the interacted window is raised to the front at drag start.
    @Published private(set) var raiseWindowOnDrag: Bool = true

    /// Minimum window width in points. Windows narrower than this are ignored.
    @Published private(set) var minWindowWidth: Int = 100

    /// Minimum window height in points. Windows shorter than this are ignored.
    @Published private(set) var minWindowHeight: Int = 100

    /// Resize border as a percentage of the window dimension (0–50 %).
    /// The effective border is max(dimension × percent, minPixels), clamped to 40 % at runtime.
    @Published private(set) var resizeBorderPercent: Double = 25.0

    /// Minimum resize border in points. Ensures a usable border on small windows.
    @Published private(set) var resizeBorderMinPixels: Int = 40

    /// Width of the left/right screen edge zones in which a dragged window shrinks (edge shrink).
    @Published private(set) var edgeZoneWidth: Int = 120

    /// Width in points a window is shrunk to when pushed fully into an edge zone.
    @Published private(set) var edgeShrinkMinWidth: Int = 400

    /// Height of the bottom screen edge zone in which releasing a window minimizes it.
    @Published private(set) var bottomZoneHeight: Int = 40

    /// Key combination that must be held to initiate a drag.
    @Published private(set) var triggerShortcut: TriggerShortcut = .defaultFN

    /// Modifier combination per drag feature (snap to windows / same app / grid, edge shrink).
    /// A feature is active only while exactly its combination is held; empty = disabled.
    @Published private var featureModifiers: [ModifierFeature: ModifierCombination] = [:]

    /// The mouse button number that initiates a drag/resize without a modifier key. nil = disabled.
    /// Button numbers: 2 = middle, 3 = button 4, 4 = button 5, etc.
    @Published private(set) var mouseButtonTrigger: Int? = nil

    /// Apps in which the mouse button trigger is disabled. Keyed by bundle identifier.
    @Published private(set) var mouseButtonExcludedApps: [ExcludedApp] = []

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
        if let p = UserDefaults.standard.object(forKey: resizeBorderPercentKey) as? Double {
            resizeBorderPercent = p
        }
        if let m = UserDefaults.standard.object(forKey: resizeBorderMinPixelsKey) as? Int {
            resizeBorderMinPixels = m
        }
        if let w = UserDefaults.standard.object(forKey: edgeZoneWidthKey) as? Int {
            edgeZoneWidth = w
        }
        if let w = UserDefaults.standard.object(forKey: edgeShrinkMinWidthKey) as? Int {
            edgeShrinkMinWidth = w
        }
        if let h = UserDefaults.standard.object(forKey: bottomZoneHeightKey) as? Int {
            bottomZoneHeight = h
        }
        triggerShortcut  = loadTriggerShortcut()
        for feature in ModifierFeature.allCases {
            featureModifiers[feature] = loadModifierCombination(for: feature)
        }
        mouseButtonTrigger = UserDefaults.standard.object(forKey: mouseButtonTriggerKey) as? Int
        mouseButtonExcludedApps = loadExcludedApps()
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
        if stored < 3 { migrate2to3() }
        if stored < 4 { migrate3to4() }

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
            (lk_v1_windowSnapKey,     lk_v3_windowSnapKey),
            (lk_v1_gridSnapKey,       lk_v3_gridSnapKey),
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

    /// v2 → v3: replace the single resizeBorderWidth pixel value with percent + minPixels.
    /// Converts the old pixel value to a reasonable minimum; percent defaults to 25 %.
    private func migrate2to3() {
        let ud = UserDefaults.standard
        if let oldPx = ud.object(forKey: lk_v2_resizeBorderWidth) as? Int {
            ud.set(oldPx, forKey: resizeBorderMinPixelsKey)
            ud.removeObject(forKey: lk_v2_resizeBorderWidth)
        }
        NSLog("[GridConfigStore] Migrated settings from 2 to 3")
    }

    /// v3 → v4: convert the single-ModifierKey snap keys to exact ModifierCombinations.
    /// Each key becomes a one-key combination; the trigger modifier is not added.
    private func migrate3to4() {
        let ud = UserDefaults.standard
        let moves: [(from: String, to: ModifierFeature)] = [
            (lk_v3_windowSnapKey,    .windowSnap),
            (lk_v3_appWindowSnapKey, .appWindowSnap),
            (lk_v3_gridSnapKey,      .gridSnap),
        ]
        for (old, feature) in moves {
            if let raw = ud.string(forKey: old), let key = ModifierKey(rawValue: raw) {
                saveModifierCombination(ModifierCombination(key.nsModifierFlag), for: feature)
            }
            ud.removeObject(forKey: old)
        }
        NSLog("[GridConfigStore] Migrated settings from 3 to 4")
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

    func setResizeBorderPercent(_ value: Double) {
        resizeBorderPercent = value
        UserDefaults.standard.set(value, forKey: resizeBorderPercentKey)
    }

    func setResizeBorderMinPixels(_ value: Int) {
        resizeBorderMinPixels = value
        UserDefaults.standard.set(value, forKey: resizeBorderMinPixelsKey)
    }

    func setEdgeZoneWidth(_ value: Int) {
        edgeZoneWidth = value
        UserDefaults.standard.set(value, forKey: edgeZoneWidthKey)
    }

    func setEdgeShrinkMinWidth(_ value: Int) {
        edgeShrinkMinWidth = value
        UserDefaults.standard.set(value, forKey: edgeShrinkMinWidthKey)
    }

    func setBottomZoneHeight(_ value: Int) {
        bottomZoneHeight = value
        UserDefaults.standard.set(value, forKey: bottomZoneHeightKey)
    }

    func setTriggerShortcut(_ shortcut: TriggerShortcut) {
        triggerShortcut = shortcut
        saveTriggerShortcut(shortcut)
    }

    func modifiers(for feature: ModifierFeature) -> ModifierCombination {
        featureModifiers[feature] ?? feature.defaultCombination
    }

    func setModifiers(_ combination: ModifierCombination, for feature: ModifierFeature) {
        featureModifiers[feature] = combination
        saveModifierCombination(combination, for: feature)
    }

    /// Returns the other feature that already uses `combination`, if any.
    /// Empty combinations (disabled features) never conflict.
    func conflictingFeature(for combination: ModifierCombination,
                            excluding feature: ModifierFeature) -> ModifierFeature? {
        guard !combination.isEmpty else { return nil }
        return ModifierFeature.allCases.first { $0 != feature && modifiers(for: $0) == combination }
    }

    func setMouseButtonTrigger(_ value: Int?) {
        mouseButtonTrigger = value
        if let v = value {
            UserDefaults.standard.set(v, forKey: mouseButtonTriggerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: mouseButtonTriggerKey)
        }
    }

    func setMouseButtonExcludedApps(_ apps: [ExcludedApp]) {
        mouseButtonExcludedApps = apps
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: mouseButtonExcludedAppsKey)
        }
    }

    func isMouseButtonExcluded(bundleID: String) -> Bool {
        mouseButtonExcludedApps.contains { $0.bundleID == bundleID }
    }

    private func loadExcludedApps() -> [ExcludedApp] {
        guard let data = UserDefaults.standard.data(forKey: mouseButtonExcludedAppsKey),
              let decoded = try? JSONDecoder().decode([ExcludedApp].self, from: data)
        else { return [] }
        return decoded
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

    private func loadModifierCombination(for feature: ModifierFeature) -> ModifierCombination {
        guard let data = UserDefaults.standard.data(forKey: feature.storageKey),
              let decoded = try? JSONDecoder().decode(ModifierCombination.self, from: data)
        else { return feature.defaultCombination }
        return decoded
    }

    private func saveModifierCombination(_ combination: ModifierCombination, for feature: ModifierFeature) {
        if let data = try? JSONEncoder().encode(combination) {
            UserDefaults.standard.set(data, forKey: feature.storageKey)
        }
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
