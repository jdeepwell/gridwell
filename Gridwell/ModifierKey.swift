import AppKit
import CoreGraphics

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
