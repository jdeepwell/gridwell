import AppKit

class ModifierKeyMonitor {

    private(set) var isTriggerActive = false

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        // Local monitor fires when Gridwell itself is the active app (e.g. Settings window open).
        // Global monitors are skipped for events in the owning app, so we need both.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event    // pass through — do not consume modifier key events
        }
        NSLog("[ModifierKeyMonitor] Started — trigger key: %@", GridConfigStore.shared.triggerKey.displayName)
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// Clears the trigger state. Call when the app loses focus so a key that was held while
    /// Gridwell was active does not leave isTriggerActive stale.
    func resetTrigger() {
        if isTriggerActive {
            isTriggerActive = false
            NSLog("[ModifierKeyMonitor] Trigger reset on app resign-active")
        }
    }

    deinit { stop() }

    private func handleFlagsChanged(_ event: NSEvent) {
        let key = GridConfigStore.shared.triggerKey
        let wasActive = isTriggerActive
        isTriggerActive = event.modifierFlags.contains(key.nsModifierFlag)
        if wasActive != isTriggerActive {
            NSLog("[ModifierKeyMonitor] Trigger key (%@) %@",
                  key.displayName, isTriggerActive ? "pressed" : "released")
        }
    }
}
