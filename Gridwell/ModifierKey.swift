import AppKit
import CoreGraphics

// MARK: - TriggerShortcut

/// Represents the key combination that initiates a drag.
/// Can be modifier-only (e.g. FN, Control+Option) or modifier + a regular key (e.g. Control+F).
struct TriggerShortcut: Codable, Equatable {

    /// Raw value of NSEvent.ModifierFlags describing the required modifier keys.
    var modifierFlagsRaw: UInt
    /// Key code of a required non-modifier key; nil for modifier-only triggers.
    var keyCode: UInt16?
    /// Human-readable display name for `keyCode`, stored at record time (e.g. "F", "Space").
    var keyDisplayString: String?

    var modifierFlags: NSEvent.ModifierFlags { .init(rawValue: modifierFlagsRaw) }

    /// The modifier flags that the recorder and monitor should pay attention to.
    static let relevantModifiers: NSEvent.ModifierFlags = [.function, .control, .option, .shift, .command]

    /// Default trigger: FN / Globe key only — matches the historic single-key default.
    static let defaultFN = TriggerShortcut(
        modifierFlagsRaw: NSEvent.ModifierFlags.function.rawValue,
        keyCode: nil,
        keyDisplayString: nil
    )

    /// Human-readable display string in macOS convention, e.g. "fn", "⌃⌥F".
    var displayString: String {
        ModifierCombination.symbols(for: modifierFlags) + (keyDisplayString ?? "")
    }
}

// MARK: - ModifierCombination

/// A set of modifier keys that activates a drag feature (snapping, edge shrink, …).
/// Matching is exact: the feature is active only when the held modifiers equal this set.
/// An empty combination means the feature is disabled.
struct ModifierCombination: Codable, Equatable {

    /// Raw value of NSEvent.ModifierFlags, restricted to `TriggerShortcut.relevantModifiers`.
    var modifierFlagsRaw: UInt

    init(_ flags: NSEvent.ModifierFlags) {
        modifierFlagsRaw = flags.intersection(TriggerShortcut.relevantModifiers).rawValue
    }

    /// The held modifiers of a CGEvent. CGEventFlags and NSEvent.ModifierFlags share the same bit layout.
    init(cgEventFlags: CGEventFlags) {
        self.init(NSEvent.ModifierFlags(rawValue: UInt(cgEventFlags.rawValue)))
    }

    static let none = ModifierCombination([])

    var modifierFlags: NSEvent.ModifierFlags { .init(rawValue: modifierFlagsRaw) }
    var isEmpty: Bool { modifierFlagsRaw == 0 }

    /// True if the feature is enabled and `held` equals this combination exactly.
    func isActive(held: ModifierCombination) -> Bool {
        !isEmpty && held == self
    }

    /// Human-readable display string in macOS convention, e.g. "⌃⌥".
    var displayString: String { Self.symbols(for: modifierFlags) }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.function) { parts.append("fn") }
        if flags.contains(.control)  { parts.append("⌃") }
        if flags.contains(.option)   { parts.append("⌥") }
        if flags.contains(.shift)    { parts.append("⇧") }
        if flags.contains(.command)  { parts.append("⌘") }
        return parts.joined()
    }
}

// MARK: - ModifierFeature

/// Drag features that are activated by a modifier combination.
enum ModifierFeature: String, CaseIterable {
    case windowSnap
    case appWindowSnap
    case gridSnap
    case edgeShrink

    /// UserDefaults key holding the JSON-encoded `ModifierCombination`.
    var storageKey: String { rawValue + "Modifiers" }

    var defaultCombination: ModifierCombination {
        switch self {
        case .windowSnap:    return ModifierCombination(.shift)
        case .appWindowSnap: return ModifierCombination(.option)
        case .gridSnap:      return ModifierCombination(.control)
        case .edgeShrink:    return .none
        }
    }

    var displayName: String {
        switch self {
        case .windowSnap:    return "All windows"
        case .appWindowSnap: return "Same app"
        case .gridSnap:      return "Grid"
        case .edgeShrink:    return "Edge shrink"
        }
    }
}

// MARK: - ModifierKey

/// Legacy single modifier key. Only used by settings migrations
/// (pre-v1 trigger key, pre-v4 snap keys); features now use `ModifierCombination`.
enum ModifierKey: String, CaseIterable, Codable {
    case fn      = "fn"
    case shift   = "shift"
    case control = "control"
    case option  = "option"
    case command = "command"

    var nsModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn:      return .function
        case .shift:   return .shift
        case .control: return .control
        case .option:  return .option
        case .command: return .command
        }
    }
}
