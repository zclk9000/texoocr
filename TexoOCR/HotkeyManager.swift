import AppKit
import Carbon.HIToolbox

class HotkeyManager {
    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    private let hotKeyID: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void

    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16 = 37, modifiers: NSEvent.ModifierFlags = [.command, .shift], action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action

        self.hotKeyID = Self.nextID
        Self.nextID += 1
        Self.handlers[self.hotKeyID] = action

        Self.installEventHandlerIfNeeded()
        register()
    }

    func updateShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        register()
    }

    // MARK: - Carbon registration

    private func register() {
        unregister()

        var ref: EventHotKeyRef?
        let signature: OSType = 0x54584F43 // 'TXOC'
        let id = EventHotKeyID(signature: signature, id: hotKeyID)
        let carbonMods = Self.carbonModifiers(from: modifiers)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonMods,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private static func installEventHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            guard let eventRef else { return noErr }
            var hkID = EventHotKeyID()
            let result = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard result == noErr else { return noErr }
            let id = hkID.id
            DispatchQueue.main.async {
                HotkeyManager.handlers[id]?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            nil
        )
    }

    private static func carbonModifiers(from mods: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if mods.contains(.command) { carbon |= UInt32(cmdKey) }
        if mods.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if mods.contains(.option)  { carbon |= UInt32(optionKey) }
        if mods.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
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
        unregister()
        Self.handlers.removeValue(forKey: hotKeyID)
    }
}
