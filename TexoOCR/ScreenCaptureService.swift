import AppKit
import Carbon.HIToolbox

@MainActor
class ScreenCaptureService {

    enum CaptureError: LocalizedError {
        case cancelled
        case noImage
        case accessibilityDenied

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Screen capture was cancelled"
            case .noImage: return "No image found after capture"
            case .accessibilityDenied: return "Accessibility permission required"
            }
        }
    }

    /// Check if Accessibility permission is granted
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt user to grant Accessibility permission
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func captureRegion() async throws -> NSImage {
        // Check Accessibility permission first
        guard Self.isAccessibilityGranted else {
            Self.requestAccessibility()
            throw CaptureError.accessibilityDenied
        }

        let beforeCount = NSPasteboard.general.changeCount

        // Simulate Cmd+Shift+Ctrl+4 to trigger system screenshot to clipboard
        simulateScreenshotShortcut()

        // Wait for user to complete the screenshot (up to 30 seconds)
        for _ in 0..<300 {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if NSPasteboard.general.changeCount != beforeCount {
                break
            }
        }

        guard NSPasteboard.general.changeCount != beforeCount else {
            throw CaptureError.cancelled
        }

        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            throw CaptureError.noImage
        }

        return image
    }

    private func simulateScreenshotShortcut() {
        // Cmd+Shift+Ctrl+4: screenshot region to clipboard
        let keyCode = CGKeyCode(0x15) // key code for '4'

        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskControl]

        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
