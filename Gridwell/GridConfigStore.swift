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

    private let userDefaultsKey = "com.gridwell.gridConfig"

    /// Maps screen key → grid config. Missing keys fall back to defaults.
    @Published private var config: [String: ScreenGridConfig] = [:]

    private init() { load() }

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
