import AppKit

class ModifierKeyMonitor {

    private(set) var isTriggerActive = false

    private var globalMonitor: Any?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        NSLog("[ModifierKeyMonitor] Started — trigger key: %@", GridConfigStore.shared.triggerKey.displayName)
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

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
