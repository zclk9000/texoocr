import AppKit

@MainActor
class ScreenCaptureService {

    enum CaptureError: LocalizedError {
        case cancelled
        case noImage
        case launchFailed

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Screen capture was cancelled"
            case .noImage: return "No image found after capture"
            case .launchFailed: return "Could not launch screencapture tool"
            }
        }
    }

    func captureRegion() async throws -> NSImage {
        let beforeCount = NSPasteboard.general.changeCount

        // Use the system screencapture tool — interactive region selection,
        // copy result to clipboard, suppress sound.
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", "-c", "-x"]

        do {
            try task.run()
        } catch {
            throw CaptureError.launchFailed
        }

        // Wait off the main thread for the user to finish the selection
        // (or cancel with Esc).
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                task.waitUntilExit()
                continuation.resume()
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
}
