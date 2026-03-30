import AppKit

class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let action: () -> Void

    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16 = 37, modifiers: NSEvent.ModifierFlags = [.command, .shift], action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
        registerMonitors()
    }

    func updateShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private func registerMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let required: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventMods = event.modifierFlags.intersection(required)
        let targetMods = modifiers.intersection(required)

        guard eventMods == targetMods, event.keyCode == keyCode else { return }
        action()
    }

    // MARK: - Display helpers

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    static func modifiersToString(_ mods: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    static func shortcutDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        return modifiersToString(modifiers) + keyCodeToString(keyCode)
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
