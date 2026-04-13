import AppKit

class ModifierKeyMonitor {

    // kVK_Function = 0x3F (63) — the FN / Globe key
    private static let fnKeyCode: UInt16 = 63

    private(set) var isFnActive = false

    private var globalMonitor: Any?

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        NSLog("[ModifierKeyMonitor] Started — trigger key: FN/Globe")
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
        guard event.keyCode == Self.fnKeyCode else { return }
        isFnActive = event.modifierFlags.contains(.function)
        NSLog("[ModifierKeyMonitor] FN key %@", isFnActive ? "pressed" : "released")
    }
}
