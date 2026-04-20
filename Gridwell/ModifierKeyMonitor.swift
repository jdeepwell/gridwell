import AppKit
import CoreGraphics

class ModifierKeyMonitor {

    private(set) var isTriggerActive = false

    // Current input state — updated by the CGEventTap in MouseInteractionHandler.
    private var currentModifierFlags      = NSEvent.ModifierFlags()
    private var currentNonModifierKeyCode: UInt16? = nil

    func start() {
        NSLog("[ModifierKeyMonitor] Started — event detection via CGEventTap")
    }

    // MARK: - CGEventTap callbacks (called from MouseInteractionHandler)

    /// Updates modifier state from a flagsChanged CGEvent and recomputes the trigger.
    func handleFlagsChanged(_ event: CGEvent) {
        // CGEventFlags and NSEvent.ModifierFlags share the same bit layout on macOS (64-bit).
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        currentModifierFlags = flags.intersection(TriggerShortcut.relevantModifiers)
        recomputeTrigger()
    }

    /// Updates key state for a keyDown event. Only the configured trigger key code is tracked.
    func handleKeyDown(keyCode: UInt16) {
        let shortcut = GridConfigStore.shared.triggerShortcut
        guard let requiredKey = shortcut.keyCode, keyCode == requiredKey else { return }
        currentNonModifierKeyCode = keyCode
        recomputeTrigger()
    }

    /// Clears key state when the tracked key is released.
    func handleKeyUp(keyCode: UInt16) {
        guard keyCode == currentNonModifierKeyCode else { return }
        currentNonModifierKeyCode = nil
        recomputeTrigger()
    }

    /// Clears all tracked state. Call as a safety net if event delivery is interrupted.
    func resetTrigger() {
        currentModifierFlags      = []
        currentNonModifierKeyCode = nil
        if isTriggerActive {
            isTriggerActive = false
            NSLog("[ModifierKeyMonitor] Trigger reset")
        }
    }

    // MARK: - Trigger computation

    private func recomputeTrigger() {
        let shortcut = GridConfigStore.shared.triggerShortcut
        let modifiersMatch = currentModifierFlags.contains(shortcut.modifierFlags)

        let newActive: Bool
        if let requiredKey = shortcut.keyCode {
            newActive = modifiersMatch && currentNonModifierKeyCode == requiredKey
        } else {
            newActive = modifiersMatch
        }

        let wasActive = isTriggerActive
        isTriggerActive = newActive
        if wasActive != newActive {
            NSLog("[ModifierKeyMonitor] Trigger %@", newActive ? "activated" : "deactivated")
        }
    }
}
