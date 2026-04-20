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
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.function) { parts.append("fn") }
        if flags.contains(.control)  { parts.append("⌃") }
        if flags.contains(.option)   { parts.append("⌥") }
        if flags.contains(.shift)    { parts.append("⇧") }
        if flags.contains(.command)  { parts.append("⌘") }
        if let key = keyDisplayString { parts.append(key) }
        return parts.joined()
    }
}

// MARK: - ModifierKey

/// A user-configurable modifier key.
enum ModifierKey: String, CaseIterable, Codable {
    case fn      = "fn"
    case shift   = "shift"
    case control = "control"
    case option  = "option"
    case command = "command"

    var displayName: String {
        switch self {
        case .fn:      return "FN / Globe"
        case .shift:   return "Shift"
        case .control: return "Control"
        case .option:  return "Option"
        case .command: return "Command"
        }
    }

    /// Unicode symbol shown next to the key name in the UI.
    var symbol: String {
        switch self {
        case .fn:      return "fn"
        case .shift:   return "⇧"
        case .control: return "⌃"
        case .option:  return "⌥"
        case .command: return "⌘"
        }
    }

    /// Flag used by `NSEvent.modifierFlags` — for detecting trigger key press/release.
    var nsModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn:      return .function
        case .shift:   return .shift
        case .control: return .control
        case .option:  return .option
        case .command: return .command
        }
    }

    /// Flag used by `CGEventFlags` — for detecting snap modifiers during a drag.
    var cgEventFlag: CGEventFlags {
        switch self {
        case .fn:      return .maskSecondaryFn
        case .shift:   return .maskShift
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .command: return .maskCommand
        }
    }
}
